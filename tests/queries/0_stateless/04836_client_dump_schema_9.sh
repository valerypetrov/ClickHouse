#!/usr/bin/env bash
# Tags: no-darwin

# A same-server remote() reader that logs in with its own user is probed with that login, not the default user.
# A private server lets the default user need a password, which the shared test server cannot do.

CUR_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CUR_DIR"/../shell_config.sh

work="${CLICKHOUSE_TMP}/${CLICKHOUSE_TEST_UNIQUE_NAME}_server"
rm -rf "$work"
mkdir -p "$work"

pid=""
cleanup() {
    if [ -n "$pid" ]; then
        kill "$pid" 2>/dev/null
        wait "$pid" 2>/dev/null
    fi
    rm -rf "$work"
}
trap cleanup EXIT

# The probe compares an address's port with tcpPort(), so the server needs a fixed one.
port=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')

cat > "$work/config.xml" <<EOF
<clickhouse>
    <logger>
        <level>information</level>
        <log>$work/server.log</log>
        <errorlog>$work/server.err.log</errorlog>
        <console>0</console>
    </logger>
    <listen_host>0.0.0.0</listen_host>
    <tcp_port>$port</tcp_port>
    <path>$work/data/</path>
    <tmp_path>$work/data/tmp/</tmp_path>
    <user_files_path>$work/data/user_files/</user_files_path>
    <display_secrets_in_show_and_select>1</display_secrets_in_show_and_select>
    <users>
        <default>
            <password>default_secret</password>
            <profile>default</profile>
            <quota>default</quota>
            <networks><ip>::/0</ip></networks>
        </default>
        <dumper>
            <password></password>
            <profile>default</profile>
            <quota>default</quota>
            <networks><ip>::/0</ip></networks>
            <named_collection_control>1</named_collection_control>
            <show_named_collections_secrets>1</show_named_collections_secrets>
        </dumper>
        <reader>
            <password>reader_secret</password>
            <profile>default</profile>
            <quota>default</quota>
            <networks><ip>::/0</ip></networks>
        </reader>
    </users>
    <profiles><default/></profiles>
    <quotas><default/></quotas>
</clickhouse>
EOF

$CLICKHOUSE_BINARY server --config-file="$work/config.xml" > "$work/stdout.log" 2>&1 &
pid=$!

client() { $CLICKHOUSE_CLIENT_BINARY --host 127.0.0.1 --port "$port" --user dumper "$@"; }
for _ in {1..1200}; do
    client -q "SELECT 1" > /dev/null 2>&1 && break
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
done
if ! client -q "SELECT 1" > /dev/null 2>&1; then
    echo "The server did not start"
    exit 1
fi

# 0.0.0.0 is not one of the server's own addresses, so the server reaches it over the network and logs in.
client --multiquery --query "
CREATE DATABASE creds;
CREATE TABLE creds.zzz_src (id UInt64) ENGINE = MergeTree ORDER BY id;
CREATE VIEW creds.aaa_login_reader AS SELECT * FROM remote('0.0.0.0:${port}', 'creds', 'zzz_src', 'reader', 'reader_secret');
CREATE NAMED COLLECTION nc_self AS host = '0.0.0.0', port = ${port}, user = 'reader', password = 'reader_secret', db = 'creds', table = 'zzz_src';
CREATE VIEW creds.aab_collection_reader AS SELECT * FROM remote(nc_self);
"

echo '--- the probe logs in as the remote() call does ---'
if client -q "SELECT count() FROM remote('0.0.0.0:${port}', system.one)" 2>&1 | grep -q 'AUTHENTICATION_FAILED\|REQUIRED_PASSWORD'; then
    echo 'OK: remote() refuses the default user'
else
    echo 'FAIL: remote() does not refuse the default user'
fi
dump_file="$work/dump.sql"
if client --format_display_secrets_in_show_and_select=1 --dump-schema=creds > "$dump_file" 2>"$work/err"; then
    src_line=$(grep -n "CREATE TABLE creds\.zzz_src" "$dump_file" | head -1 | cut -d: -f1)
    for reader in aaa_login_reader aab_collection_reader; do
        reader_line=$(grep -n "CREATE VIEW creds\.${reader} " "$dump_file" | head -1 | cut -d: -f1)
        if [ -n "$src_line" ] && [ -n "$reader_line" ] && [ "$src_line" -lt "$reader_line" ]; then
            echo "OK: source dumped before ${reader}"
        else
            echo "FAIL: ${reader} missing or dumped before its source (src=$src_line reader=$reader_line)"
        fi
    done
else
    echo "FAIL: dump rejected: $(cat "$work/err")"
fi

echo '--- a masked password the address needs refuses the dump ---'
# Without the format setting the stored password reads back as [HIDDEN], and the default user proves nothing.
client --multiquery --query "
CREATE DATABASE masked;
CREATE TABLE masked.zzz_src (id UInt64) ENGINE = MergeTree ORDER BY id;
CREATE VIEW masked.aaa_login_reader AS SELECT * FROM remote('0.0.0.0:${port}', 'masked', 'zzz_src', 'reader', 'reader_secret');
"
if client --dump-schema=masked > "$dump_file" 2>"$work/err"; then
    echo 'FAIL: dump succeeded although the login of the reader was masked'
else
    echo "masked login refused: $(grep -c 'cannot read the login the call uses' "$work/err")"
fi
