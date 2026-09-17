/** 策略/温控类供电节点：易与系统互抢，默认不建议作开关 */
export function looksLikePolicySwitch(line: string): boolean {
  return /night_charging|cool_mode|batt_protect|smart_charging|adapter_cc_mode|step_charging|restrict_chg|restricted_charging|charge_control_/i.test(
    line,
  );
}
