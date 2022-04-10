// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "../oracles/compound/CTokenMultiOracle.sol";
import "../mocks/DAIMock.sol";
import "../mocks/USDCMock.sol";
import "../mocks/oracles/compound/CTokenMock.sol";
import "./utils/Test.sol";
import "./utils/TestConstants.sol";

contract CTokenMultiOracleTest is Test, TestConstants, AccessControl {
    CTokenMultiOracle public cTokenMultiOracle;
    DAIMock public dai;
    USDCMock public usdc;
    CTokenMock public cDai;
    CTokenMock public cUsdc;
    bytes6 public cDaiId = 0xba53a8454e7e;
    bytes6 public cUsdcId = 0x119135d7f8be;
    bytes6 public mockBytes6 = 0x24d4497ee7bd;
    
    function setUp() public {
        cTokenMultiOracle = new CTokenMultiOracle();
        dai = new DAIMock();
        usdc = new USDCMock();
        cDai = new CTokenMock(address(dai));
        cUsdc = new CTokenMock(address(usdc));
        cTokenMultiOracle.grantRole(0x92b45d9c, address(this));
        cTokenMultiOracle.setSource(cDaiId, DAI, CTokenInterface(address(cDai)));
        cTokenMultiOracle.setSource(cUsdcId, USDC, CTokenInterface(address(cUsdc)));
        cDai.set(WAD * 2 * 10 ** 10);
        cUsdc.set(WAD * 2 / 100);
    }

    function testRevertOnUnknownSource() public {
        vm.expectRevert("Source not found");
        cTokenMultiOracle.get(bytes32(mockBytes6), bytes32(mockBytes6), WAD);
    }

    function testGetCTokenConversions() public {
        (uint256 cDaiDaiConversion,) = cTokenMultiOracle.get(cDaiId, DAI, WAD);
        require(cDaiDaiConversion == WAD * 2);
        (uint256 cUsdcUsdcConversion,) = cTokenMultiOracle.get(cUsdcId, USDC, WAD);
        require(cUsdcUsdcConversion == WAD * 2);
        (uint256 daiCDaiConversion,) = cTokenMultiOracle.get(DAI, cDaiId, WAD);
        require(daiCDaiConversion == WAD / 2);
        (uint256 peekCDaiDaiConversion,) = cTokenMultiOracle.peek(cDaiId, DAI, WAD);
        require(peekCDaiDaiConversion == WAD * 2);
        (uint256 peekCUsdcUsdcConversion,) = cTokenMultiOracle.peek(cUsdcId, USDC, WAD);
        require(peekCUsdcUsdcConversion == WAD * 2);
        (uint256 peekDaiCDaiConversion,) = cTokenMultiOracle.peek(DAI, cDaiId, WAD);
        require(peekDaiCDaiConversion == WAD / 2);

    }

}