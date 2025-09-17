# genesis-contracts

> NOTE (IMPORTANT!)
> If you modify contracts, run `forge build` before testing/deploying/etc, or Foundry may not recompile them!

#### Setup genesis

Setup genesis whenever contracts get changed
### 1. Install dependencies and submodules
```bash
npm install
git submodule init
git submodule update
```

### 2. Compile PoS contracts
```bash
$ cd pos-contracts
$ npm install
$ npm run template:process -- --bor-chain-id 15001
$ npx hardhat compile
$ cd ..
```

### 3. Generate Bor validator set sol file

Following command will generate `BorValidatorSet.sol` file from `BorValidatorSet.template` file.

```bash
# Generate bor validator set using stake and balance
# Modify validators.json before as per your need
$ node generate-borvalidatorset.js --bor-chain-id <bor-chain-id> --heimdall-chain-id <heimdall-chain-id>
```

### 4. Compile contracts
```bash
$ npm run truffle:compile
```

### 5. Configure Block times

To add custom block time and associated block no.s in genesis, edit the `blocks.js` file

### 6. Generate genesis file

Following command will generate `genesis.json` file from `genesis-template.json` file.

```bash
# Generate genesis file
node generate-genesis.js --bor-chain-id <bor-chain-id> --heimdall-chain-id <heimdall-chain-id>
```

### 7. Run Tests
```bash
$ npm run testrpc
$ npm test
```
