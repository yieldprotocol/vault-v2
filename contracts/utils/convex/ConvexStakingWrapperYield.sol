//https://etherscan.io/address/0x3ba207c25a278524e1cc7faaea950753049072a4#code
// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;
pragma experimental ABIEncoderV2;

import './ConvexStakingWrapper.sol';
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";

struct Balances {
    uint128 art; // Debt amount
    uint128 ink; // Collateral amount
}

interface ICauldron {
    /// @dev Each vault records debt and collateral balances_.
    function balances(bytes12 vault) external view returns (Balances memory);
}

//Staking wrapper for Yield platform
//use convex LP positions as collateral while still receiving rewards
contract ConvexStakingWrapperYield is ConvexStakingWrapper,AccessControl {
    using SafeERC20 for IERC20;
    using Address for address;

    bytes12[] public vaults;
    address cauldron;

    constructor() public {}

    function initialize(
        address _curveToken,
        address _convexToken,
        address _convexPool,
        uint256 _poolId,
        address _vault
    ) external override auth{
        require(!isInit, 'already init');
        owner = address(0xa3C5A1e09150B75ff251c1a7815A07182c3de2FB); //default to convex multisig
        emit OwnershipTransferred(address(0), owner);
        _tokenname = string(abi.encodePacked('Staked ', ERC20(_convexToken).name(), ' Yield'));
        _tokensymbol = string(abi.encodePacked('stk', ERC20(_convexToken).symbol(), '-yield'));
        isShutdown = false;
        isInit = true;
        curveToken = _curveToken;
        convexToken = _convexToken;
        convexPool = _convexPool;
        convexPoolId = _poolId;
        collateralVault = address(0xF5BCE5077908a1b7370B9ae04AdC565EBd643966); //TODO: We will have to come up with our own vault. Perhaps join might work here

        // if(_vault != address(0)){
        //     vaults.push(_vault);
        // }

        //add rewards
        addRewards();
        setApprovals();
    }

    function vaultsLength() external view returns (uint256) {
        return vaults.length;
    }

    function setCauldron(address _cauldron) external auth{
        require(_cauldron!=address(0), 'cauldron address cannot be 0');
        cauldron = _cauldron;
        
    }

    // Set the locations of vaults where the user's funds have been deposited & the accounting is kept
    function setVault(bytes12 _vault) external auth {
        for (uint256 i = 0; i < vaults.length; i++) {
            require(vaults[i] != _vault, 'already added');
        }
        vaults.push(_vault);
    }

    function removeVault(bytes12 _vault) external auth {
        for (uint256 i = 0; i < vaults.length; i++) {
            if(vaults[i] == _vault){
                remove(i);
                break;
            }
        }
    }

    function remove(uint _index) internal{
        require(_index < vaults.length, "index out of bound");

        for (uint i = _index; i < vaults.length - 1; i++) {
            vaults[i] = vaults[i + 1];
        }
        vaults.pop();
    }

    // Get user's balance of collateral deposited at in various vaults
    function _getDepositedBalance(address _account) internal view override returns (uint256) {
        if (_account == address(0) || _account == collateralVault) {
            return 0;
        }

        if (vaults.length == 0) {
            return balanceOf(_account);
        }

        //add up all balances of all vaults
        uint256 collateral;
        for (uint256 i = 0; i < vaults.length; i++) {
            try ICauldron(cauldron).balances(vaults[i]) returns (Balances memory _balance) {
                collateral = collateral + (_balance.ink);
            } catch {}
        }
        //add to balance of this token
        return balanceOf(_account) + collateral;
    }
}
