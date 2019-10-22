pragma solidity ^0.5.2;
// Solidity Interface

contract UniswapExchangeMock {

    function getEthToTokenInputPrice(uint256 eth_sold) external view returns (uint256 tokens_bought){
      return 0.98 ether;
    }

}
