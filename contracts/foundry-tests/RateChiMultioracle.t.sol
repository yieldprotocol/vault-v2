// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "../oracles/compound/CompoundMultiOracle.sol";
import "../mocks/oracles/compound/CTokenChiMock.sol";
import "../mocks/oracles/compound/CTokenRateMock.sol";
import "./utils/Test.sol";
import "./utils/TestConstants.sol";

contract RateChiMultiOracleTest is Test, TestConstants, AccessControl {
    CTokenChiMock public cTokenChi;
    CTokenRateMock public cTokenRate;
    CompoundMultiOracle public compoundMultiOracle;

    bytes6 public baseId = 0x25dde80ea598;
    bytes6 public mockBytes6 = 0x000000000001;

    function setUp() public {
        cTokenChi = new CTokenChiMock();
        cTokenRate = new CTokenRateMock();
        compoundMultiOracle = new CompoundMultiOracle();
        compoundMultiOracle.grantRole(0x92b45d9c, address(this));
        compoundMultiOracle.setSource(baseId, CHI, address(cTokenChi));
        compoundMultiOracle.setSource(baseId, RATE, address(cTokenRate));
        cTokenChi.set(WAD * 2);
        cTokenRate.set(WAD * 3);
    }

    function testRevertUnknownSource() public {
        vm.expectRevert("Source not found");
        compoundMultiOracle.get(mockBytes6, mockBytes6, WAD);
    }

    function testSetRetrieveChiRate() public {
        (uint256 getChiPrice,) = compoundMultiOracle.get(bytes32(baseId), bytes32(CHI), WAD);
        require(getChiPrice == WAD * 2, "Failed to get CHI spot price");
        (uint256 getRatePrice,) = compoundMultiOracle.get(bytes32(baseId), bytes32(RATE), WAD);
        require(getRatePrice == WAD * 3, "Failed to get RATE spot price");
        (uint256 peekChiPrice,) = compoundMultiOracle.peek(bytes32(baseId), bytes32(CHI), WAD);
        require(peekChiPrice == WAD * 2, "Failed to peek CHI spot price");
        (uint256 peekRatePrice,) = compoundMultiOracle.peek(bytes32(baseId), bytes32(RATE), WAD);
        require(peekRatePrice == WAD * 3, "Failed to peek RATE spot price");
    }
}