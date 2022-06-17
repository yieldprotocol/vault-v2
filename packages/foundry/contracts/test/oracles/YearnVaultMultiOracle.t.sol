// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "forge-std/src/Test.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "../../oracles/yearn/YearnVaultMultiOracle.sol";
import "../../mocks/DAIMock.sol";
import "../../mocks/USDCMock.sol";
import "../../mocks/YvTokenMock.sol";
import "../utils/TestConstants.sol";

contract YearnVaultMultiOracleTest is Test, TestConstants, AccessControl {

    event SourceSet(bytes6 indexed baseId, bytes6 indexed quoteId, address indexed source, uint8 decimals);

    DAIMock public dai;
    USDCMock public usdc;
    YearnVaultMultiOracle public yearnVaultMultiOracle;
    YvTokenMock public yvDAI;
    YvTokenMock public yvUSDC;

    function setUp() public {
        dai = new DAIMock();
        usdc = new USDCMock();
        yearnVaultMultiOracle = new YearnVaultMultiOracle();
        yvDAI = new YvTokenMock("Yearn Vault DAI", "yvDAI", 18, ERC20(address(dai)));
        // Amount of yvDAI you receive for 1 DAI
        uint256 daiToYvdaiPrice = 1071594513314087964;
        yvDAI.set(daiToYvdaiPrice);
        yvUSDC = new YvTokenMock("Yearn Vault USDC", "yvUSDC", 6, ERC20(address(usdc)));
        // Amount of yvUSDC you receive for 1 USDC
        uint256 usdcToYvusdcPrice = 1083891;
        yvUSDC.set(usdcToYvusdcPrice);
        yearnVaultMultiOracle.grantRole(0x92b45d9c, address(this));
    }

    function testRevertOnUnknownPair() public {
        vm.expectRevert("Source not found");
        yearnVaultMultiOracle.get(YVUSDC, USDC, 2000000);
    }

    function testSetPairAndInverse() public {
        bytes6 baseId = USDC;
        bytes6 quoteId = YVUSDC;
        address source = address(yvUSDC);
        uint8 decimals = IYvToken(source).decimals();
        vm.expectEmit(true, true, true, false);
        emit SourceSet(baseId, quoteId, address(source), decimals);
        yearnVaultMultiOracle.setSource(baseId, quoteId, IYvToken(source));
        yearnVaultMultiOracle.get(USDC, YVUSDC, 2000000);
    }

    function setYearnVaultMultiOracleSource() public {
        yearnVaultMultiOracle.setSource(USDC, YVUSDC, IYvToken(address(yvUSDC)));
        yearnVaultMultiOracle.setSource(DAI, YVDAI, IYvToken(address(yvDAI)));
    }

    function testGetAndPeek() public {
        setYearnVaultMultiOracleSource();
        (uint256 yvusdcUsdcConversion,) = yearnVaultMultiOracle.get(YVUSDC, USDC, 2000000);
        uint256 yvusdcToUsdcPrice = 1083891 * 2; // Amount of USDC you receive for 2000000 yvUSDC
        assertEq(yvusdcUsdcConversion, yvusdcToUsdcPrice, "Get yvUSDC-USDC conversion unsuccessful");

        (uint256 yvdaiDaiConversion,) = yearnVaultMultiOracle.get(YVDAI, DAI, WAD * 2);
        uint256 yvdaiToDaiPrice = 1071594513314087964 * 2; // Amount of DAI you receive for 1e18 * 2 yvDAI
        assertEq(yvdaiDaiConversion, yvdaiToDaiPrice, "Peek yvDAI-DAI conversion unsuccessful");

        (uint256 usdcYvusdcConversion,) = yearnVaultMultiOracle.get(USDC, YVUSDC, 1000000);
        uint256 usdcToYvusdcPrice = 922601; // Amount of yvUSDC received for 1000000 USDC
        assertEq(usdcYvusdcConversion, usdcToYvusdcPrice, "Get USDC-yvUSDC conversion unsuccessful");

        (uint256 daiYvdaiConversion,) = yearnVaultMultiOracle.peek(DAI, YVDAI, WAD);
        uint256 daiToYvdaiPrice = WAD * WAD / 1071594513314087964; // Amount of yvDAI received for 1e18 DAI
        assertEq(daiYvdaiConversion, daiToYvdaiPrice, "Peek DAI-yvDAI conversion unsuccessful");

        yvUSDC.set(1088888); // Sets new price for USDC to yvUSDC conversion
        (uint256 newPrice,) = yearnVaultMultiOracle.get(YVUSDC, USDC, 2000000);
        assertEq(newPrice, 1088888 * 2, "Get new price unsuccessful");
    }

    function testRevertOnZeroPrice() public {
        setYearnVaultMultiOracleSource();
        yvUSDC.set(0);
        vm.expectRevert("Zero price");
        yearnVaultMultiOracle.get(YVUSDC, USDC, 2000000);
    }

}
