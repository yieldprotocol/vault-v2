// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

// TODO: Replace with forge-std.
interface Vm {
    function expectEmit(
        bool,
        bool,
        bool,
        bool
    ) external;

    function expectRevert(bytes memory) external;

    function prank(address) external;

    function startPrank(address) external;

    function stopPrank() external;

    function deal(address, uint256) external;

    function addr(uint256) external returns (address);

    function getCode(string calldata) external returns (bytes memory);

    function assume(bool) external;
}

contract Test {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function deployCode(string memory what) public returns (address addr) {
        bytes memory bytecode = vm.getCode(what);
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))
        }
    }
}