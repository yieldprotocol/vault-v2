pragma solidity ^0.6.2;

import "./../maker/pot.sol";


contract MockPot is Pot {

    constructor(address vat) public Pot(vat) {}

    function dripAndJoin(uint wad) external {
        this.drip();
        this.join(wad);
    }
}