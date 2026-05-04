class ElectricConsumptionSettings {
  const ElectricConsumptionSettings({
    this.fanConsumption15,
    this.fanConsumption25,
    this.fanConsumption35,
    this.fanConsumption50,
    this.fanConsumption65,
    this.fanConsumption75,
    this.fanConsumption85,
    this.pumpConsumption,
    this.heatingConsumption1,
    this.heatingConsumption2,
  });

  const ElectricConsumptionSettings.defaults()
    : fanConsumption15 = null,
      fanConsumption25 = null,
      fanConsumption35 = null,
      fanConsumption50 = null,
      fanConsumption65 = null,
      fanConsumption75 = null,
      fanConsumption85 = null,
      pumpConsumption = null,
      heatingConsumption1 = null,
      heatingConsumption2 = null;

  final double? fanConsumption15;
  final double? fanConsumption25;
  final double? fanConsumption35;
  final double? fanConsumption50;
  final double? fanConsumption65;
  final double? fanConsumption75;
  final double? fanConsumption85;
  final double? pumpConsumption;
  final double? heatingConsumption1;
  final double? heatingConsumption2;
}
