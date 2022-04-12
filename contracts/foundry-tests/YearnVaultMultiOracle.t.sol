// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "../oracles/yearn/YearnVaultMultiOracle.sol";
import "../mocks/DAIMock.sol";
import "../mocks/USDCMock.sol";
import "../mocks/YvTokenMock.sol";
import "./utils/Test.sol";
import "./utils/TestConstants.sol";

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
        yvDAI.set(1071594513314087964);
        yvUSDC = new YvTokenMock("Yearn Vault USDC", "yvUSDC", 6, ERC20(address(usdc)));
        yvUSDC.set(1083891);
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
        require(yvusdcUsdcConversion == 1083891 * 2, "Get yvUSDC-USDC conversion unsuccessful");
        (uint256 yvdaiDaiConversion,) = yearnVaultMultiOracle.get(YVDAI, DAI, WAD * 2);
        require(yvdaiDaiConversion == 1071594513314087964 * 2, "Peek yvDAI-DAI conversion unsuccessful");
        (uint256 usdcYvusdcConversion,) = yearnVaultMultiOracle.get(USDC, YVUSDC, 1000000);
        require(usdcYvusdcConversion == 922601, "Get USDC-yvUSDC conversion unsuccessful");
        (uint256 daiYvdaiConversion,) = yearnVaultMultiOracle.peek(DAI, YVDAI, WAD);
        require(daiYvdaiConversion == WAD * WAD / 1071594513314087964, "Peek DAI-yvDAI conversion unsuccessful");
        yvUSDC.set(1088888);
        (uint256 newPrice,) = yearnVaultMultiOracle.get(YVUSDC, USDC, 2000000);
        require(newPrice == 1088888 * 2, "Get new price unsuccessful");
    }

    function testRevertOnZeroPrice() public {
        setYearnVaultMultiOracleSource();
        yvUSDC.set(0);
        vm.expectRevert("Zero price");
        yearnVaultMultiOracle.get(YVUSDC, USDC, 2000000);
    }

}
