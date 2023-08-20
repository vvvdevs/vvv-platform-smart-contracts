## VVV Allocation Contracts

Branch for some minor adds moving into requesting audit quotes.

### ***FOR OUR AUDITOR FRIENDS***
1. Requirements: 
    - audit/Requirements.md
2. Audit Scope: 
    - contracts/InvestmentHandler.sol (454 LOC)
    - node_modules/@uintgroup/pausable-selective/src/PausableSelective.sol (58 LOC)
3. Concerns: 
    - audit/PreAuditConcerns.md
4. Operation Notes (role separation, wallet security)
    - audit/OperationNotes.md
5. Relevant Code Metrics: 
    - audit/solidity-metrics.html
    - cloc returns 523 total LOC

### Changes to code this branch
1. Packed `claim()` call input arguments into a `ClaimParams` struct.
2. Removed unneeded import and "using" statement of SafeMath
3. Modified tests to work with `ClaimParams` addition

