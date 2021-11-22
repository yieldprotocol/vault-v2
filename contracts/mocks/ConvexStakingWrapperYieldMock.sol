// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
contract ConvexStakingWrapperYieldMock is ERC20{
    mapping(address=>bytes12[]) public vaults;
    address cauldron;
    constructor() 
        ERC20(
            "StakedConvexToken",
            "stkCvx"
        ){
    }
    function deposit(uint256 _amount, address _to) external {

        if (_amount > 0) {
            _mint(_to, _amount);
            // IERC20(curveToken).safeTransferFrom(msg.sender, address(this), _amount);
            
        }
    }

    function stake(uint256 _amount, address _to) external {
        if (_amount > 0) {
            _mint(_to, _amount);
            // IERC20(convexToken).safeTransferFrom(msg.sender, address(this), _amount);   
        }
    }

    function withdraw(uint256 _amount) external {
        if (_amount > 0) {
            _burn(msg.sender, _amount);
            // IRewardStaking(convexPool).withdraw(_amount, false);
            // IERC20(convexToken).safeTransfer(msg.sender, _amount);
        }
    }

    function withdrawAndUnwrap(uint256 _amount) external {
        if (_amount > 0) {
            _burn(msg.sender, _amount);
            // IRewardStaking(convexPool).withdrawAndUnwrap(_amount, false);
            // IERC20(curveToken).safeTransfer(msg.sender, _amount);
        }
    }

    function setCauldron(address _cauldron) external {
        require(_cauldron!=address(0), 'cauldron address cannot be 0');
        cauldron = _cauldron;
        
    }

    // Set the locations of vaults where the user's funds have been deposited & the accounting is kept
    function setVault(address _account, bytes12 _vault) external {
        bytes12[] storage userVault = vaults[_account];
        for (uint256 i = 0; i < userVault.length; i++) {
            require(userVault[i] != _vault, 'already added');
        }
        userVault.push(_vault);
        vaults[_account] = userVault;
    }

    function removeVault(address _account, bytes12 _vault) external {
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
}