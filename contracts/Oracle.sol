pragma solidity ^0.5.2;
pragma experimental ABIEncoderV2;

//Using fake contract instead of abstract for mocking
contract Oracle {
  uint256 val;

  function set(uint256 _value) public {
    val = _value;
  }

  function read() external view returns (uint256) {
      require(val > 0, "Invalid price feed");
      return val;
  }

  function peek() external view returns (uint256,bool) {
      return (val, val > 0);
  }

}
