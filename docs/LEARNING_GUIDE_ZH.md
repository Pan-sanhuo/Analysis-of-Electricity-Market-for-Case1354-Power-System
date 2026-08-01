# Case1354 项目学习导读

## 1. 这个项目在做什么

项目将 Case1354 的 Excel 电网数据转换为 MATPOWER 算例，并在 24 个小时内进行电力市场调度。核心目标不是只计算某一时刻的潮流，而是在满足网络、机组和市场约束的条件下，安排发电与需求响应，使报价成本和约束松弛成本最小。

可以把它理解为两层工作：第一层是 `case1354_multiperiod_market` 的日前或实时市场 DC 调度；第二层是 `case1354cljs` 的逐小时 AC 最优潮流校核。前者侧重经济出清和跨时段约束，后者侧重电压、无功和交流网络可行性。

## 2. 推荐阅读顺序

1. 阅读根目录 `README.md`，先明确 DC 市场模型与 AC 校核模型的差别。
2. 打开 `src/market/case1354_multiperiod_market.m`，它是 24 小时联合出清的总入口。
3. 阅读 `src/model/read_case1354_excel.m` 和 `src/model/build_matpower_case.m`，理解 Excel 如何变成 `mpc.bus`、`mpc.gen` 和 `mpc.branch`。
4. 阅读 `src/model/build_gencost_matrix.m`、`src/model/apply_load_schedule.m`、`src/model/apply_generator_schedule.m`，理解报价、负荷和机组时序数据。
5. 再阅读 `src/market/add_auxiliary_services_to_most.m`、`add_demand_response_to_most.m`、`build_n1_contingencies.m`，了解可选市场功能。
6. 最后查看 `src/results/` 和 `results/main/`，把代码变量与 Excel 结果表对应起来。

## 3. 24 小时市场模型流程

主程序的逻辑可以概括为：

```text
Excel 输入
  -> 输入校验与 MATPOWER 基础算例
  -> 逐小时负荷、可用容量、报价曲线 profile
  -> MOST 多时段 SCED 或 SCUC 模型
  -> 可选：辅助服务、需求响应、N-1 场景
  -> 联合优化求解
  -> 出清、结算、约束审计和可追溯性结果
```

`SCED` 中机组开停状态保持给定状态，重点是连续出力 `Pg`、爬坡和网络约束。`SCUC` 还会确定部分机组是否开机，因此需要整数规划求解器，并会考虑启停和最小开停时间。

## 4. Excel 数据如何进入模型

- `Bus` 和 `Branch` 定义物理网络。
- `Generator`、`Initial` 和 `GeneratorSchedule` 定义机组容量、初始状态和分时可用能力/计划。
- `GenBid` 定义普通竞价机组的分段能量报价；程序会检查名称标准化、时段匹配、段容量和段价格。
- `LoadEntity`、`LoadSchedule` 和 `LoadBid` 定义负荷实体、24 小时需求及可调负荷报价。负荷实体通过 LDF 分配到具体母线。
- `ASRequirement` 和 `ASBid` 定义调频与备用需求和报价。
- `TransmissionConstr`、`BranchGroup`、`Nomogram` 等定义市场输电限制或组合约束。

如果输入名称、单位或 LDF 不正确，模型可能失去负荷、报价匹配失败或出现数值病态。因此，运行后先检查 `DataValidation`、负荷分配审计和报价审计，而不是只看目标函数。

## 5. 如何理解主要结果

先看 `MultiPeriodSummary` 是否成功，再看 `MultiPeriodDispatch` 的每台机组出力。`NodalEnergyPrice` 中只有 `ResultValid=true` 的价格才可以用于解释；失败小时的 LMP、目标函数和影子价格应是 `NaN`，不能用于结算。

对市场结果，至少同时阅读 `GeneratorSettlement`、`MarketSettlementSummary` 和 `BranchLimitStatus`。它们分别说明机组收入、负荷支付与拥塞租，以及线路是“达到限值”还是“真正违反限值”。若启用了辅助服务和需求响应，还应检查备用短缺、弃负荷/削减量及其惩罚成本。

## 6. 常见误解

- 最小目标函数值不等于真实总发电成本，它通常是报价成本加上模型中定义的惩罚项。
- LMP 不是所有母线相同的固定电价；存在网络阻塞时，不同母线的 LMP 可以不同。
- SCED 成功不意味着 AC 潮流一定成功。需要运行 AC 校核。
- `Success=false` 不是“负荷为零”。失败结果中的业务数值应视为无效，重点阅读失败阶段和诊断信息。
- 对无有效报价的机组，生产模式不应随意补零成本；调试模式的默认报价只用于定位问题。

## 7. 建议的学习实验

1. 先只运行 `targetHours=1:2`，关闭辅助服务、需求响应和 N-1，理解最基础的 SCED。
2. 打开辅助服务，比较能量出力与备用容量之间的 `Pmax` 耦合。
3. 打开需求响应，观察负荷削减、消费者效用和系统价格变化。
4. 打开筛选后的 N-1 约束，比较基态与故障场景的线路负载和备用需求。
5. 使用 `case1354cljs` 对选定小时执行 AC 校核，并比较 DC 出清和 AC 结果。

每次只改变一个开关，并保存结果文件，最容易发现模型假设对结果的影响。
