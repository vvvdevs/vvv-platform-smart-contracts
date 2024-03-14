# VVV Smart Contract
## Audit instructions
### Test & coverage
Run all commands in the root of the repository.

#### Initial setup
1. [Install npm](https://docs.npmjs.com/downloading-and-installing-node-js-and-npm)
2. `$ npm install`
3. Install [Foundry](https://book.getfoundry.sh/getting-started/installation), or at least Forge

#### $VVV vesting
To run tests and collect coverage for the $VVV vesting contract and its first party dependencies:
```
$ forge coverage --match-contract 'VVVVesting*|VVVAuthorization*|VVVToken*' | awk '!/^\| contracts|test|Total/ || /^\| contracts\/vesting|auth|tokens\//'
```

#### ETH staking
To run tests and collect coverage for the ETH staking contract and its first party dependencies:
```
$ forge coverage --match-contract 'VVVETHStaking*|VVVAuthorization*|VVVToken*' | awk '!/^\| contracts|test|Total/ || /^\| contracts\/staking|auth|tokens\//'
```

## Contributing

Before contributing install the pre-commit hook by running the command below in the root of the repository.

```
yarn prepare
```

This will prevent you from gettingblocked by the CI on your pull request.
