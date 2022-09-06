# Telos EVM Staking Contracts

This repository includes two smart contracts that make up the backend of the TLOS staking functionality on Telos EVM as well as a guide on how to deploy the whole staking system.

## Requirements

This repository requires NodeJS 14+ installed

## Deployment

To deploy the staking system you first need to deploy the __StakedTLOS__ and __TelosEscrow__ contracts on Telos EVM

### StakedTLOS & TelosEscrow

#### Clone the project

`git clone https://github.com/telosnetwork/stlos`

#### Install dependencies

`npm install`

#### Test

`npx hardhat test`

#### Deploy

`npx hardhat deploy --network testnet`

_Remember to save the StakedTLOS contract address, we'll need it to configure the Native Telos exrsrv.tf contract later_

#### Verify

`npx hardhat sourcify  --network testnet`

_Gateway timeouts are normal, the contract should still get verified, check using a block explorer or try to run the command again_


#### Transfer Ownership

After that you should transfer ownership of those contracts to the `prods.evm` linked EVM address for configuration of the `lockDuration` and `maxDeposits` variables via native multisig.

#### Set configuration using a Native multisig

Make sure the `prods.evm` linked EVM address has enough TLOS to pay for gas and follow our [native-to-evm-escrow-example](https://github.com/telosnetwork/native-to-evm-escrow-example) repository for an example of how to propose a multisig that calls a function of our TelosEscrow contract. The example uses the `setLockDuration` function but you can easily adapt it for `setMaxDeposits` or any other functions.

The following EVM functions are available for configuration on TelosEscrow:

`setLockDuration(uint)`

Set the lock duration for deposits, in seconds

`setMaxDeposits(uint)`

Set the max deposits per address

`transferOwnership(address)`

Transfer ownership of the contract to the specified address

_/!\ The EVM address linked to the native multisig account should be owner so that only a native multisig can change the configuration._


### EXRSRV.TF

Once __StakedTLOS__ & __TelosEscrow__ are deployed and configured all that is left is to set and configure the [__exrsrv.tf__](https://github.com/telosnetwork/telos-distribute) contract on Telos Native that is responsible for distributing the staking rewards.

Staking can be configured using the following actions:

- `setratio(uint64_t ratio_value)` 
  -  The `ratio_value` is multiplied to the rewards sent to EVM, a ratio of 90 will for example decrease EVM rewards by 10%
- `setevmconfig(string stlos_contract, eosio::checksum256 storage_key, uint64_t wtlos_index)`
  -  `stlos_contract` is your StakedTLOS EVM contract address
  -  `storage_key` is the computed storage key for the STLOS contract WTLOS balance
  -  `wtlos_index` is the index of WTLOS in the eosio.evm accounts table

#### Get the WTLOS index

The WTLOS index can be found on __eosio.evm__'s accounts table using the WTLOS EVM address (without the 0x), you can use a block explorer or a JS script to retreive it.

#### Get the storage key

The storage key we are looking for is part of the `address => uint` balance mapping at position 3 of the WTLOS contract. We need to access the mapping value corresponding to the STLOS address in order to retreive its WTLOS balance.

To compute that storage key, you can use the following snippet that uses the ethers library:

```
const { BigNumber, ethers, utils } = require("ethers");
const Web3 = require ('web3');

const web3 = new Web3();

(async function() {
    const provider = ethers.getDefaultProvider("https://testnet.telos.net/evm");

    const contract = "0xaE85Bf723A9e74d6c663dd226996AC1b8d075AA9"; // WTLOS testnet address

    // Get the array slot
    const slot = ethers.utils.keccak256(
        ethers.utils.concat( [
            ethers.utils.hexZeroPad("0x9EECD00cdBA81c691EC0Bfdc2485c36010885A58", 32), // STLOS testnet address
            ethers.utils.hexZeroPad("0x03", 32), // The position of the balance mapping inside WTLOS
        ])
    );

    console.log("Storage key is: ", slot)
})();
```

And then check you have the right slot using


``` 
    let balance = 0;

    try {
        balance = await provider.getStorageAt(contract, slot);

    } catch (e) {}

    console.log(balance)
```

You can also use a block explorer to try and find the key that matches your STLOS EVM contract's WTLOS balance but it is less reliable.

## EVM Contracts

### :: StakedTLOS

The StakedTLOS contract is an ERC20 token that implements the [ERC4626](https://docs.openzeppelin.com/contracts/4.x/api/token/erc20#ERC4626) tokenized vault standard

#### Rundown

- First, deposited TLOS are converted to sTLOS which represent shares of the TLOS pool
- The value of those sTLOS shares changes according to the balance of TLOS in the contract
- On withdraw, sTLOS is converted to TLOS and sent to the TelosEscrow contract

#### Public functions

`totalAssets(): uint256  `

Returns the total TLOS + WTLOS balance of the contract

`function previewDeposit(uint256 assets):uint256`

Preview shares returned on deposit of asset (rounded down)

`function previewMint(uint256 shares): uint256`

Preview assets value underlying the shares (rounded up)

`function previewRedeem(uint256 shares):uint256`

Preview assets returned on redeeming of shares (rounded down)

`function previewWithdraw(uint256 assets): uint256`

Preview the shares to withdraw from balance to withdraw assets (rounded up)

`function convertToShares(uint256 assets): uint256`

Converts assets to shares

`function convertToAssets(uint256 shares): uint256`

Converts shares to assets

`function maxDeposit(address): uint256`

Returns the max total deposit amount per address

`function maxMint(address): uint256` 

Returns the max mint amount per address

`function balanceOf(address owner): uint256`

Returns the share balance of an address

`function maxWithdraw(address owner): uint256`

Returns the max withdraw amount for an address

`function depositTLOS(): uint256`

Deposit TLOS to the contract

`function withdraw(uint256 assets,  address receiver, address owner)`

Withdraw assets to Telos Escrow contract

#### Deployments

__Testnet :__ 0xa9991E4daA44922D00a78B6D986cDf628d46C4DD

__Mainnet :__ 0x98BD57444603C66b736Fd0AeFCBE494c8Ee32C71

### :: TelosEscrow

The TelosEscrow contract locks token on deposit for a configurable amount of time (`lockDuration`)

#### Rundown

- TLOS is deposited in the contract and gets locked for  `lockDuration` amount of time
- Once unlocked, depositors can withdraw the TLOS to their account

#### Public functions

`lockDuration(): uint256 `

Returns the lock duration

`maxDeposits(): uint256 `

Returns the maximum number of deposits

`balanceOf(address depositor): uint256 `

Returns the total TLOS balance of a depositor (locked & unlocked)

`maxWithdraw(address depositor): uint256 `

Returns the current maximum TLOS withdraw (unlocked tokens) for a depositor

`depositsOf(address depositor): []`

Returns the deposits `{uint256 amount, uint256 until }` of a depositor

`deposit(address depositor): uint256 `

Deposits TLOS for depositor.

`withdraw(): uint256 `

Withdraw all unlocked TLOS

#### Events

`Withdraw(address _from, address _to, uint _amount)`

Emitted on sucessfull call to `withdraw()`

`Deposit(address _from, address _depositor, uint _amount)`

Emitted on sucessfull call to `deposit(address depositor)`

#### Deployments

__Testnet :__ 0x7E9cF9fBc881652B05BB8F26298fFAB538163b6f

__Mainnet :__ 0x7B74aAD58Ea0c76180967Aa0e342E1b7f389B48A
