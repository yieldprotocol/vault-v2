// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;


interface ISplitterProxy {
    function hope(address) external;
    function nope(address) external;
}

contract SplitterProxyMock {
    ISplitterProxy public immutable splitter;

    constructor(ISplitterProxy splitter_) public {
        splitter = splitter_;
    }

    // SplitterProxy1: Fork and Split

    // Splitter accepts to take the user vault. Callable only by the user or its dsproxy
    // Anyone can call this to donate a collateralized vault to Splitter.
    function hope(address user) public {
        splitter.hope(msg.sender);
    }

    // Splitter doesn't accept to take the user vault. Callable only by the user or its dsproxy
    function nope(address user) public {
        splitter.nope(msg.sender);
    }
}
