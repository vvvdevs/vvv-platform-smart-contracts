# Pre-Optimizations
Outputs of: `forge test --match-contract VVVVesting --gas-report`

| contracts/vesting/VVVVesting.sol:VVVVesting contract |                 |        |        |         |         |
|------------------------------------------------------|-----------------|--------|--------|---------|---------|
| Deployment Cost                                      | Deployment Size |        |        |         |         |
| 1009680                                              | 5274            |        |        |         |         |
| Function Name                                        | min             | avg    | median | max     | # calls |
| VVVToken                                             | 349             | 349    | 349    | 349     | 1       |
| batchSetVestingSchedule                              | 8966            | 544967 | 286825 | 1597254 | 4       |
| calculateVestedAmountAtInterval                      | 553             | 1866   | 2178   | 3173    | 7       |
| getVestedAmount                                      | 1454            | 2383   | 2444   | 2540    | 10      |
| removeVestingSchedule                                | 5592            | 5592   | 5592   | 5592    | 2       |
| setVestedToken                                       | 8905            | 12016  | 12025  | 15110   | 4       |
| setVestingSchedule                                   | 8626            | 154976 | 173059 | 173059  | 18      |
| userVestingSchedules                                 | 1732            | 1732   | 1732   | 1732    | 11      |
| withdrawVestedTokens                                 | 1516            | 30233  | 3137   | 65844   | 9       |

# Post-Optimizations 1
Changes Made: VestingSchedule data packing, without touching token amounts which can be affected by precision loss

| contracts/vesting/VVVVesting.sol:VVVVesting contract |                 |        |        |        |         |
|------------------------------------------------------|-----------------|--------|--------|--------|---------|
| Deployment Cost                                      | Deployment Size |        |        |        |         |
| 1091160                                              | 5693            |        |        |        |         |
| Function Name                                        | min             | avg    | median | max    | # calls |
| VVVToken                                             | 349             | 349    | 349    | 349    | 1       |
| batchSetVestingSchedule                              | 9032            | 290187 | 150973 | 849771 | 4       |
| calculateVestedAmountAtInterval                      | 553             | 1866   | 2178   | 3173   | 7       |
| getVestedAmount                                      | 1495            | 2417   | 2480   | 2599   | 10      |
| removeVestingSchedule                                | 5328            | 5328   | 5328   | 5328   | 2       |
| setVestedToken                                       | 8883            | 11994  | 12003  | 15088  | 4       |
| setVestingSchedule                                   | 8456            | 94193  | 104696 | 104696 | 18      |
| userVestingSchedules                                 | 1392            | 1392   | 1392   | 1392   | 11      |
| withdrawVestedTokens                                 | 1534            | 30164  | 3196   | 65658  | 9       |
 
# Difference (Pre to 1)

| contracts/vesting/VVVVesting.sol:VVVVesting contract |                 |        |        |        |         |
|-----------------------------------------------------|-----------------|--------|--------|--------|---------|
| Deployment Cost                                     | Deployment Size |        |        |        |         |
| 81480                                               | 419             |        |        |        |         |
| Function Name                                       | min             | avg    | median | max    | # calls |
| VVVToken                                            | 0               | 0      | 0      | 0      | 0       |
| batchSetVestingSchedule                             | 66              | -254780 | -135852 | -747483 | 0    |
| calculateVestedAmountAtInterval                     | 0               | 0      | 0      | 0      | 0       |
| getVestedAmount                                     | 41              | 34     | 36     | 59     | 0       |
| removeVestingSchedule                               | -264            | -264   | -264   | -264   | 0       |
| setVestedToken                                      | -22             | -22    | -22    | -22    | 0       |
| setVestingSchedule                                  | -170            | -60783 | -68363 | -68363 | 0       |
| userVestingSchedules                                | -340            | -340   | -340   | -340   | 0       |
| withdrawVestedTokens                                | 18              | -69    | 59     | -186   | 0       |

