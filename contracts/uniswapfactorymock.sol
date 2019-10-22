pragma solidity ^0.5.2;
// Solidity Interface

import './uniswapexchangemock.sol';

contract UniswapFactoryMock {
    mapping (address => address) exchanges;
    // Create Exchange
    function createExchange(address token) external returns (address exchange)
    {
      UniswapExchangeMock _mock = new UniswapExchangeMock();
      exchanges[token] = address(_mock);
      return address(_mock);
    }
    // Get Exchange and Token Info
    function getExchange(address token) external view returns (address exchange){
      return exchanges[token];
    }
    // Never use
}
