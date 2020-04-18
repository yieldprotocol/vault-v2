import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract TestERC20 is ERC20 {
    constructor (uint256 supply) public {
        _mint(msg.sender, supply);
    }
}