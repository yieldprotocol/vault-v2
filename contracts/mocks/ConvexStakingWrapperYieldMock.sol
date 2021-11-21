// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
contract ConvexStakingWrapperYieldMock is ERC20{
    bytes12[] public vaults;
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
    function setVault(bytes12 _vault) external  {
        for (uint256 i = 0; i < vaults.length; i++) {
            require(vaults[i] != _vault, 'already added');
        }
        vaults.push(_vault);
    }

    function removeVault(bytes12 _vault) external  {
        for (uint256 i = 0; i < vaults.length; i++) {
            if(vaults[i] == _vault){
                remove(i);
                break;
            }
        }
    }

    function remove(uint _index) internal {
        require(_index < vaults.length, "index out of bound");

        for (uint i = _index; i < vaults.length - 1; i++) {
            vaults[i] = vaults[i + 1];
        }
        vaults.pop();
    }
}