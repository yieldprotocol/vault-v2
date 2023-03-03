// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/src/token/TransferHelper.sol";
import "../../Witch.sol";
import "./interfaces/IContangoWitchListener.sol";
import "./interfaces/IContangoWitch.sol";

contract ContangoWitch is Witch, IContangoWitch {
    using Math for uint256;
    using TransferHelper for *;
    using Cast for uint256;

    struct InsuranceLine {
        bool disabled;
        uint32 duration; // Time that the insurance auction take to cover the maximum debt insured
        uint64 maxInsuredProportion; // Maximum proportion of debt that is covered by the insurance fund at the insurance auction end (1e18 = 100%)
        uint64 insurancePremium; // Proportion of the collateral that is sent to the insurance fund for healthy liquidations (1e18 = 100%)
    }

    mapping(bytes6 => mapping(bytes6 => InsuranceLine)) public insuranceLines;
    address public insuranceFund;
    uint64 defaultInsurancePremium; // 1e18 = 100%

    constructor(
        ICauldron cauldron_,
        ILadle ladle_,
        address insuranceFund_
    ) Witch(cauldron_, ladle_) {
        insuranceFund = insuranceFund_;
    }

    function _auctionStarted(
        bytes12 vaultId,
        DataTypes.Auction memory auction_,
        DataTypes.Line memory line
    ) internal override returns (DataTypes.Vault memory vault) {
        vault = super._auctionStarted(vaultId, auction_, line);
        try
            IContangoWitchListener(auction_.owner).auctionStarted(vaultId)
        {} catch {
            emit AuctionStartedCallbackFailed(auction_.owner, vaultId);
        }
    }

    function _collateralBought(
        bytes12 vaultId,
        address owner,
        address buyer,
        uint256 ink,
        uint256 art
    ) internal override {
        super._collateralBought(vaultId, owner, buyer, ink, art);
        try
            IContangoWitchListener(owner).collateralBought(
                vaultId,
                buyer,
                ink,
                art
            )
        {} catch {
            emit CollateralBoughtCallbackFailed(owner, vaultId, ink, art);
        }
    }

    function _auctionEnded(bytes12 vaultId, address owner) internal override {
        super._auctionEnded(vaultId, owner);
        try
            IContangoWitchListener(owner).auctionEnded(vaultId, owner)
        {} catch {
            emit AuctionEndedCallbackFailed(owner, vaultId);
        }
    }

    function setDefaultInsurancePremium(
        uint64 defaultInsurancePremium_
    ) external override auth {
        require(
            defaultInsurancePremium_ <= ONE_HUNDRED_PERCENT,
            "Default Insurance Premium above 100%"
        );
        defaultInsurancePremium = defaultInsurancePremium_;
        emit DefaultInsurancePremiumSet(defaultInsurancePremium);
    }

    function setInsuranceLineStatus(
        bytes6 ilkId,
        bytes6 baseId,
        bool disabled
    ) external override auth {
        insuranceLines[ilkId][baseId].disabled = disabled;
        emit InsuranceLineStatusSet(ilkId, baseId, disabled);
    }

    function setInsuranceLine(
        bytes6 ilkId,
        bytes6 baseId,
        uint32 duration,
        uint64 maxInsuredProportion,
        uint64 insurancePremium
    ) external override auth {
        require(
            maxInsuredProportion <= ONE_HUNDRED_PERCENT,
            "Max Insured Proportion above 100%"
        );
        require(
            insurancePremium <= ONE_HUNDRED_PERCENT,
            "Insurance Premium above 100%"
        );

        insuranceLines[ilkId][baseId] = InsuranceLine({
            disabled: false,
            duration: duration,
            maxInsuredProportion: maxInsuredProportion,
            insurancePremium: insurancePremium
        });
        emit InsuranceLineSet(
            ilkId,
            baseId,
            duration,
            maxInsuredProportion,
            insurancePremium
        );
    }

    function setInsuranceFund(address insuranceFund_) external override auth {
        insuranceFund = insuranceFund_;
        emit InsuranceFundSet(insuranceFund);
    }

    function _discountDebt(
        bytes6 ilkId,
        bytes6 baseId,
        bytes6 seriesId,
        uint256 auctionStart,
        uint256 auctionDuration,
        uint256 artIn
    ) internal virtual override returns (uint256 requiredArtIn) {
        InsuranceLine memory line = insuranceLines[ilkId][baseId];
        uint256 topUp = line.duration == 0
            ? 0
            : artIn.wmul(_debtDiscountNow(line, auctionStart, auctionDuration));

        if (topUp > 0) {
            uint256 insuranceFYTokenBalance = cauldron
                .series(seriesId)
                .fyToken
                .balanceOf(insuranceFund);
            uint256 insuranceBaseBalance = IERC20(ladle.joins(baseId).asset())
                .balanceOf(insuranceFund);

            uint256 topUpAvailable = insuranceFYTokenBalance +
                cauldron.debtFromBase(seriesId, insuranceBaseBalance.u128());
            if (topUp > topUpAvailable) topUp = topUpAvailable;
        }

        requiredArtIn = artIn - topUp;
    }

    function _debtDiscountNow(
        InsuranceLine memory line,
        uint256 auctionStart,
        uint256 auctionDuration
    ) internal view returns (uint256 debtDiscountNow) {
        uint256 elapsed = block.timestamp - (auctionStart + auctionDuration);
        debtDiscountNow = elapsed < line.duration
            ? (line.maxInsuredProportion * elapsed) / line.duration
            : line.maxInsuredProportion;
    }

    function _topUpDebt(
        bytes12 vaultId,
        DataTypes.Auction memory auction,
        uint256 artIn,
        bool baseTopUp
    ) internal override returns (uint256 requiredArtIn) {
        InsuranceLine memory insuranceLine = insuranceLines[auction.ilkId][
            auction.baseId
        ];
        uint256 duration = lines[auction.ilkId][auction.baseId].duration;

        if (
            insuranceLine.duration == 0 ||
            auction.start + duration > block.timestamp
        ) {
            requiredArtIn = artIn;
        } else {
            requiredArtIn = artIn.wdivup(
                ONE_HUNDRED_PERCENT -
                    _debtDiscountNow(insuranceLine, auction.start, duration)
            );
            if (requiredArtIn > auction.art) requiredArtIn = auction.art;

            uint256 topUpAmount = requiredArtIn - artIn;

            if (topUpAmount != 0) {
                uint256 debtToppedUp = baseTopUp
                    ? cauldron.debtToBase(auction.seriesId, topUpAmount.u128())
                    : topUpAmount;

                IFYToken fyToken = cauldron.series(auction.seriesId).fyToken;
                uint256 fyTokenBalance = fyToken.balanceOf(insuranceFund);

                uint256 payWithFYToken = fyTokenBalance > debtToppedUp
                    ? debtToppedUp
                    : fyTokenBalance;
                if (payWithFYToken != 0) {
                    // Take fyTokens from insurance fund
                    fyToken.safeTransferFrom(
                        insuranceFund,
                        address(fyToken),
                        payWithFYToken
                    );
                    fyToken.burn(address(this), payWithFYToken);
                }

                uint256 payWithBase = debtToppedUp - payWithFYToken;
                if (payWithBase != 0) {
                    IJoin baseJoin = ladle.joins(auction.baseId);
                    if (baseJoin == IJoin(address(0))) {
                        revert JoinNotFound(auction.baseId);
                    }

                    // Take underlying from insurance fund
                    IERC20(baseJoin.asset()).safeTransferFrom(
                        insuranceFund,
                        address(baseJoin),
                        payWithBase
                    );
                    baseJoin.join(address(this), payWithBase.u128());
                }

                emit LiquidationInsured(vaultId, topUpAmount, debtToppedUp);
            }
        }
    }

    function _calcInsurancePremium(
        DataTypes.Auction memory auction_,
        uint256 liquidatorCut
    ) internal view override returns (uint256 premium) {
        InsuranceLine memory insuranceLine = insuranceLines[auction_.ilkId][
            auction_.baseId
        ];

        (
            bool shouldPayInsurancePremium,
            uint256 insurancePremium
        ) = _shouldPayInsurancePremium(insuranceLine, auction_);
        if (shouldPayInsurancePremium) {
            premium = liquidatorCut.wmul(insurancePremium);
        }
    }

    function _payInk(
        DataTypes.Auction memory auction,
        address to,
        uint256 liquidatorCut,
        uint256 auctioneerCut,
        uint256 insurancePremium
    ) internal override returns (uint256, uint256) {
        if (insurancePremium > 0) {
            _join(auction.ilkId).exit(insuranceFund, insurancePremium.u128());
        }

        return
            super._payInk(
                auction,
                to,
                liquidatorCut,
                auctioneerCut,
                insurancePremium
            );
    }

    function _shouldPayInsurancePremium(
        InsuranceLine memory insuranceLine,
        DataTypes.Auction memory auction
    ) internal view returns (bool should, uint256 insurancePremium) {
        if (insuranceLine.disabled) return (false, 0);

        uint256 duration = lines[auction.ilkId][auction.baseId].duration;
        insurancePremium = insuranceLine.insurancePremium > 0
            ? insuranceLine.insurancePremium
            : defaultInsurancePremium;

        // Only charge premium for non-insured liquidations
        should =
            insurancePremium > 0 &&
            block.timestamp <= auction.start + duration;
    }
}
