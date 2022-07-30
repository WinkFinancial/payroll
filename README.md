# Payroll
Multiple payments and swaps in one transaction


## Pre requisits
You will need nodejs version 16 https://nodejs.dev/
And yarn https://classic.yarnpkg.com/lang/en/docs/install/#mac-stable


Create .env using the .env.example and replace for the corresponding values
```sh
cp .env.example .env
```

Then, proceed with installing dependencies:

```sh
yarn install
```

## Development

Compile the smart contracts with Hardhat:

```sh
$ yarn compile
```

Linting (EsLint and Solhint)

```sh
$ yarn lint
```

Generate Documentation

```sh
$ yarn docgen
```

Contract Sizes

```sh
$ yarn size
```


### Test

Run the Mocha tests:

```sh
$ yarn test
```

Run coverage tests:

```sh
$ yarn coverage
```

### Slither
Slither is a source code analyser for solidity, it runs a suite of vulnerability detectors, prints visual information about contract details.
First install it using https://github.com/crytic/slither#how-to-install

Then run
```sh
$ slither .
```

## Deploy

Deploy the contracts to Hardhat Network:

```sh
$ yarn deploy network hardhat
```

Deploy the contracts to biannce testnet Network:

```sh
$ yarn deploy network bscTestnet
```

## Deployments

Ethereum Mainnet: 0x5bCe0AbAbA89e1d0e063978d87CfF2f8f5145942 https://etherscan.io/address/0x5bCe0AbAbA89e1d0e063978d87CfF2f8f5145942

Binance Smart Chain Mainnet: 0xe2EBFC705d473C3dDd52CB49AF0bdE3132E8831e https://bscscan.com/address/0xe2EBFC705d473C3dDd52CB49AF0bdE3132E8831e

Rinkeby: 0x977AfF4027BeFCcB5D5a476c69447382232Ef339 https://rinkeby.etherscan.io/address/0x977AfF4027BeFCcB5D5a476c69447382232Ef339

Binance Smart Chain Testnet: 0x4d995D5B936889B9A26A12B7b48a22A80F226fde https://testnet.bscscan.com/address/0x4d995D5B936889B9A26A12B7b48a22A80F226fde

Telos EVM Testnet: 0xdcF72c0De33a53BACfa7562ab86375e4Fe90bC65 https://testnet.telos.net/v2/explore/evm/address/0xdcf72c0de33a53bacfa7562ab86375e4fe90bc65

RSK Testnet: 0x18c42168D834c99E2e7a368a5Fbf39F5BB32e09D https://explorer.testnet.rsk.co/tx/0x1fa00aeb16c05abe451a37fc42ad6b0736dd136fbb31cfe2c5ac077aafe06fae

Polygon Mumbai Testnet: 0x46c60C1b5f756c8B6AA10A7d838380AD1B5F28BE https://mumbai.polygonscan.com/address/0x46c60C1b5f756c8B6AA10A7d838380AD1B5F28BE

