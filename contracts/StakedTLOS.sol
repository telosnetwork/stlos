// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./IERC4626.sol";
import "./Math.sol";

interface IWTLOS {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
    function balanceOf(address) external returns (uint);
}

interface ITelosEscrow {
    function deposit(address) payable external;
    function withdraw(uint) external;
}

contract StakedTLOS is ERC20, IERC4626 {
    using Math for uint256;

    IERC20Metadata private immutable _asset;

    ITelosEscrow public _escrow;

    address public _admin;

    constructor(IERC20Metadata asset_, ITelosEscrow escrow_, address admin_) ERC20("Staked TLOS", "STLOS") {
        require(Address.isContract(address(asset_)), 'constructor: asset be a valid contract');
        require(Address.isContract(address(escrow_)), 'constructor: escrow be a valid contract');
        _asset = asset_;
        _escrow = escrow_;
        _admin = admin_;
    }

    function setEscrow(ITelosEscrow escrow_) public {
        require(msg.sender == _admin, 'This can only be called by the admin address');
        require(Address.isContract(address(escrow_)), 'escrow needs to be a valid contract');
        _escrow = escrow_;
    }

    function setAdmin(address admin_) public  {
        require(msg.sender == _admin, 'This can only be called by the admin address');
        _admin = admin_;
    }

    /** @dev See {IERC4262-asset} */
    function asset() public view virtual override returns (address) {
        return address(_asset);
    }

    /** @dev See {IERC4262-totalAssets} */
    function totalAssets() public view virtual override returns (uint256) {
        return _asset.balanceOf(address(this)) + address(this).balance;
    }

    /** @dev See {IERC4262-convertToShares} */
    function convertToShares(uint256 assets) public view virtual override returns (uint256 shares) {
        return _convertToShares(assets, 0, Math.Rounding.Down);
    }

    /** @dev See {IERC4262-convertToAssets} */
    function convertToAssets(uint256 shares) public view virtual override returns (uint256 assets) {
        return _convertToAssets(shares, Math.Rounding.Down);
    }

    /** @dev See {IERC4262-maxDeposit} */
    function maxDeposit(address) public view virtual override returns (uint256) {
        return type(uint256).max;
    }

    /** @dev See {IERC4262-maxMint} */
    function maxMint(address) public view virtual override returns (uint256) {
        return type(uint256).max;
    }

    /** @dev See {IERC4262-maxWithdraw} */
    function maxWithdraw(address owner) public view virtual override returns (uint256) {
        return _convertToAssets(balanceOf(owner), Math.Rounding.Down);
    }

    /** @dev See {IERC4262-maxRedeem} */
    function maxRedeem(address owner) public view virtual override returns (uint256) {
        return balanceOf(owner);
    }

    /** @dev See {IERC4262-previewDeposit} */
    function previewDeposit(uint256 assets) public view virtual override returns (uint256) {
        return _convertToShares(assets, 0, Math.Rounding.Down);
    }

    /** @dev See {IERC4262-previewMint} */
    function previewMint(uint256 shares) public view virtual override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Up);
    }

    /** @dev See {IERC4262-previewWithdraw} */
    function previewWithdraw(uint256 assets) public view virtual override returns (uint256) {
        return _convertToShares(assets, 0, Math.Rounding.Up);
    }

    /** @dev See {IERC4262-previewRedeem} */
    function previewRedeem(uint256 shares) public view virtual override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Down);
    }

    function _unwrap(uint amount) internal {
        uint256 myBalance = IWTLOS(asset()).balanceOf(address(this));
        if (amount <= myBalance) {
            IWTLOS(asset()).withdraw(amount);
        }
    }

    function _wrap() internal {
        uint256 myBalance = address(this).balance - msg.value;
        if (myBalance > 0) {
            IWTLOS(asset()).deposit{value: myBalance }();
        }
    }

    receive() external payable {}

    function depositTLOS() public payable returns (uint256) {
        require(msg.value > 0, "ERC4626: assets to deposit is zero");
        require(msg.value <= maxDeposit(msg.sender), "ERC4626: deposit more then max");

        _wrap();
        address caller = _msgSender();
        uint256 shares = _convertToShares(msg.value, msg.value, Math.Rounding.Down);

        IWTLOS(asset()).deposit{value: msg.value}();

        _mint(caller, shares);

        emit Deposit(caller, caller, msg.value, shares);

        return shares;
    }

    /** @dev See {IERC4262-deposit} */
    function deposit(uint256 assets, address receiver) public virtual override returns (uint256) {
        require(assets <= maxDeposit(receiver), "ERC4626: deposit more then max");

        _wrap();
        address caller = _msgSender();
        uint256 shares = previewDeposit(assets);

        // if _asset is ERC777, transferFrom can call reenter BEFORE the transfer happens through
        // the tokensToSend hook, so we need to transfer before we mint to keep the invariants.
        SafeERC20.safeTransferFrom(_asset, caller, address(this), assets);
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);

        return shares;
    }

    /** @dev See {IERC4262-mint} */
    function mint(uint256 shares, address receiver) public virtual override returns (uint256) {
        require(shares <= maxMint(receiver), "ERC4626: mint more then max");

        _wrap();
        address caller = _msgSender();
        uint256 assets = previewMint(shares);

        // if _asset is ERC777, transferFrom can call reenter BEFORE the transfer happens through
        // the tokensToSend hook, so we need to transfer before we mint to keep the invariants.
        SafeERC20.safeTransferFrom(_asset, caller, address(this), assets);
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);

        return assets;
    }

    /** @dev See {IERC4262-withdraw} */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual override returns (uint256) {
        _wrap();
        require(assets <= maxWithdraw(owner), "ERC4626: withdraw more then max");

        address caller = _msgSender();
        uint256 shares = previewWithdraw(assets);

        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // if _asset is ERC777, transfer can call reenter AFTER the transfer happens through
        // the tokensReceived hook, so we need to transfer after we burn to keep the invariants.
        _burn(owner, shares);

        _unwrap(assets);
        _escrow.deposit{value: assets}(address(receiver));

        emit Withdraw(caller, receiver, owner, assets, shares);

        return shares;
    }

    /** @dev See {IERC4262-redeem} */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual override returns (uint256) {
        _wrap();
        require(shares <= maxRedeem(owner), "ERC4626: redeem more then max");

        address caller = _msgSender();
        uint256 assets = previewRedeem(shares);

        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // if _asset is ERC777, transfer can call reenter AFTER the transfer happens through
        // the tokensReceived hook, so we need to transfer after we burn to keep the invariants.
        _burn(owner, shares);

        _unwrap(assets);

        _escrow.deposit{value: assets}(receiver);

        emit Withdraw(caller, receiver, owner, assets, shares);

        return assets;
    }

    /**
     * @dev Internal convertion function (from assets to shares) with support for rounding direction
     *
     * Will revert if assets > 0, totalSupply > 0 and totalAssets = 0. That corresponds to a case where any asset
     * would represent an infinite amout of shares.
     */
    function _convertToShares(uint256 assets, uint256 toIgnore, Math.Rounding direction) internal view virtual returns (uint256 shares) {
        uint256 supply = totalSupply();
        return
            (assets == 0 || supply == 0)
                ? assets.mulDiv(10**decimals(), 10**_asset.decimals(), direction)
                : assets.mulDiv(supply, totalAssets() - toIgnore, direction);
    }

    /**
     * @dev Internal convertion function (from shares to assets) with support for rounding direction
     */
    function _convertToAssets(uint256 shares, Math.Rounding direction) internal view virtual returns (uint256 assets) {
        uint256 supply = totalSupply();
        return
            (supply == 0)
                ? shares.mulDiv(10**_asset.decimals(), 10**decimals(), direction)
                : shares.mulDiv(totalAssets(), supply, direction);
    }
}
