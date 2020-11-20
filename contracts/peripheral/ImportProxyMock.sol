// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;


interface IImportProxy {
    function hope(address) external;
    function nope(address) external;
}

contract ImportProxyMock {
    IImportProxy public immutable splitter;

    constructor(IImportProxy splitter_) public {
        splitter = splitter_;
    }

    // ImportProxy1: Fork and Split

    // Splitter accepts to take the user vault. Callable only by the user or its dsproxy
    // Anyone can call this to donate a collateralized vault to Splitter.
    function hope(address) public {
        splitter.hope(msg.sender);
    }

    // Splitter doesn't accept to take the user vault. Callable only by the user or its dsproxy
    function nope(address) public {
        splitter.nope(msg.sender);
    }
}
