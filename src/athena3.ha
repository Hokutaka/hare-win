// Athena-3 telemetry. Runtime / stdlib are not required.
// 予定外の動作をゼロとして扱うのは危険。
export @symbol("athena3_budget_uj") fn remaining_uj(capacity: i64, standby: i64, sensors: i64, radio: i64, autonomous: i64) i64 = {
    return capacity - standby - sensors - radio - autonomous;
};

export @symbol("yokai_max_left") fn cans_left(stock: i64, consumed: i64) i64 = {
    return stock - consumed;
};
