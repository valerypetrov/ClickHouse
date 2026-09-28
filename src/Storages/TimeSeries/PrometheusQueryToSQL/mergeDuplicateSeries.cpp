#include <Storages/TimeSeries/PrometheusQueryToSQL/mergeDuplicateSeries.h>

#include <Parsers/ASTFunction.h>
#include <Parsers/ASTIdentifier.h>
#include <Parsers/ASTLiteral.h>


namespace DB::PrometheusQueryToSQL
{

ASTPtr makeMergedValues(const ASTPtr & values)
{
    /// if(length(groupArray(values)) = 1, groupArray(values)[1], arrayReduce('anyForEach', groupArray(values)))
    auto all_values = [&] { return makeASTFunction("groupArray", values->clone()); };

    return makeASTFunction(
        "if",
        makeASTFunction("equals", makeASTFunction("length", all_values()), make_intrusive<ASTLiteral>(1u)),
        makeASTFunction("arrayElement", all_values(), make_intrusive<ASTLiteral>(1u)),
        makeASTFunction("arrayReduce", make_intrusive<ASTLiteral>("anyForEach"), all_values()));
}

ASTPtr makeDuplicateSeriesCheck(const ASTPtr & values, ASTPtr group)
{
    /// timeSeriesThrowDuplicateSeriesIf(
    ///     length(groupArray(values)) > 1 AND arrayExists(c -> c > 1, arrayReduce('countForEach', groupArray(values))), group) = 0
    auto all_values = [&] { return makeASTFunction("groupArray", values->clone()); };

    auto overlap = makeASTFunction(
        "and",
        makeASTFunction("greater", makeASTFunction("length", all_values()), make_intrusive<ASTLiteral>(1u)),
        makeASTFunction(
            "arrayExists",
            makeASTLambda({"c"}, makeASTFunction("greater", make_intrusive<ASTIdentifier>("c"), make_intrusive<ASTLiteral>(1u))),
            makeASTFunction("arrayReduce", make_intrusive<ASTLiteral>("countForEach"), all_values())));

    return makeASTFunction(
        "equals",
        makeASTFunction("timeSeriesThrowDuplicateSeriesIf", std::move(overlap), std::move(group)),
        make_intrusive<ASTLiteral>(0u));
}

}
