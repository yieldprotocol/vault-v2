// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >= 0.8.0;
import "@yield-protocol/utils-v2/contracts/RevertMsgExtractor.sol";


contract PoolRouterMock  {

    mapping(address => mapping(address => address)) public pools;

    function addPool(address base, address fyToken, address pool)
        external
    {
        pools[base][fyToken] = pool;
    }

    /// @dev Allow users to route calls to a pool, to be used with multicall
    function route(address base, address fyToken, bytes memory data)
        external payable
        returns (bool success, bytes memory result)
    {
        (success, result) = pools[base][fyToken].call(data);
        if (!success) revert(RevertMsgExtractor.getRevertMsg(result));
    }    
}