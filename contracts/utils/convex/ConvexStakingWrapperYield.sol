//https://etherscan.io/address/0x3ba207c25a278524e1cc7faaea950753049072a4#code
// SPDX-License-Identifier: BUSL-1.1
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


    mapping(address=>bytes12[]) public vaults;
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
        owner = address(0xa3C5A1e09150B75ff251c1a7815A07182c3de2FB); //TODO: Find why this needs to be set to convex multisig
        emit OwnershipTransferred(address(0), owner);//TODO: Find why this needs to be done
        _tokenname = string(abi.encodePacked('Staked ', ERC20(_convexToken).name(), ' Yield'));
        _tokensymbol = string(abi.encodePacked('stk', ERC20(_convexToken).symbol(), '-yield'));
        isShutdown = false;
        isInit = true;
        curveToken = _curveToken;
        convexToken = _convexToken;
        convexPool = _convexPool;
        convexPoolId = _poolId;
        collateralVault = _vault; //TODO: Add the join address

        //add rewards
        addRewards();
        setApprovals();
    }

    function setCauldron(address _cauldron) external auth{
        require(_cauldron!=address(0), 'cauldron address cannot be 0');
        cauldron = _cauldron;
    }

    // Set the locations of vaults where the user's funds have been deposited & the accounting is kept
    function setVault(address _account, bytes12 _vault) external auth {
        bytes12[] storage userVault = vaults[_account];
        for (uint256 i = 0; i < userVault.length; i++) {
            require(userVault[i] != _vault, 'already added');
        }
        userVault.push(_vault);
        vaults[_account] = userVault;
    }

    function removeVault(address _account, bytes12 _vault) external auth {
        bytes12[] storage userVault = vaults[_account];
        for (uint256 i = 0; i < userVault.length; i++) {
            if(userVault[i] == _vault){
                vaults[_account] = remove(i,userVault);
                break;
            }
        }
    }

    function remove(uint _index,bytes12[] storage userVault) internal returns (bytes12[] memory){
        require(_index < userVault.length, "index out of bound");

        for (uint i = _index; i < userVault.length - 1; i++) {
            userVault[i] = userVault[i + 1];
        }
        userVault.pop();
        return userVault;
    }

    // Get user's balance of collateral deposited at in various vaults
    function _getDepositedBalance(address _account) internal view override returns (uint256) {
        if (_account == address(0) || _account == collateralVault) {
            return 0;
        }

        if (vaults[_account].length == 0) {
            return balanceOf(_account);
        }
    bytes12[] memory userVault = vaults[_account];
        //add up all balances of all vaults
        uint256 collateral;
        for (uint256 i = 0; i < userVault.length; i++) {
            try ICauldron(cauldron).balances(userVault[i]) returns (Balances memory _balance) {
                collateral = collateral + (_balance.ink);
            } catch {}
        }
        //add to balance of this token
        return balanceOf(_account) + collateral;
    }
}