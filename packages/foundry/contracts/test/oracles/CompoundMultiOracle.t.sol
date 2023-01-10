// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import { CompoundMultiOracle } from "../../oracles/compound/CompoundMultiOracle.sol";
import { CTokenChiMock } from "../../mocks/oracles/compound/CTokenChiMock.sol";
import { CTokenRateMock } from "../../mocks/oracles/compound/CTokenRateMock.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";
import { TestConstants } from "../utils/TestConstants.sol";

contract CompoundMultiOracleTest is Test, TestConstants {
    CTokenChiMock public cTokenChi;
    CTokenRateMock public cTokenRate;
    CompoundMultiOracle public compoundMultiOracle;

    bytes6 public baseId;
    uint256 unitForBase;

    function setUpMock() public {
        cTokenChi = new CTokenChiMock();
        cTokenRate = new CTokenRateMock();
        compoundMultiOracle = new CompoundMultiOracle();
        compoundMultiOracle.grantRole(compoundMultiOracle.setSource.selector, address(this));
        baseId = 0x000000000001;
        
        compoundMultiOracle.setSource(baseId, CHI, address(cTokenChi));
        compoundMultiOracle.setSource(baseId, RATE, address(cTokenRate));
        cTokenChi.set(WAD * 2);
        cTokenRate.set(WAD * 3);
    }

    function setUpHarness() public {
        compoundMultiOracle = CompoundMultiOracle(vm.envAddress("ORACLE"));
        baseId = bytes6(vm.envBytes32("BASE"));
        unitForBase = 10 ** ERC20Mock(address(vm.envAddress("BASE_ADDRESS"))).decimals();
    }

    function setUp() public {
        string memory rpc = vm.envOr(RPC, MAINNET);
        vm.createSelectFork(rpc);

        if (vm.envOr(MOCK, true)) setUpMock();
        else setUpHarness();
    }

    function testRevertUnknownSource() public {
        bytes6 mockBytes6 = 0x000000000002;
        vm.expectRevert("Source not found");
        compoundMultiOracle.get(mockBytes6, mockBytes6, WAD);
    }

    function testSetRetrieveChiRate() public {
        (uint256 getChi,) = compoundMultiOracle.get(bytes32(baseId), bytes32(CHI), unitForBase);
        assertGt(getChi, 0, "Failed to get CHI spot price");
        (uint256 getRate,) = compoundMultiOracle.get(bytes32(baseId), bytes32(RATE), unitForBase);
        assertGt(getRate, 0, "Failed to get RATE spot price");
        (uint256 peekChi,) = compoundMultiOracle.peek(bytes32(baseId), bytes32(CHI), unitForBase);
        assertGt(peekChi, 0, "Failed to peek CHI spot price");
        (uint256 peekRate,) = compoundMultiOracle.peek(bytes32(baseId), bytes32(RATE), unitForBase);
        assertGt(peekRate, 0, "Failed to peek RATE spot price");
    }
}