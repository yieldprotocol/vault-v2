// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IContangoWitchEvents {
    event InsuranceLineSet(uint32 duration, uint64 maxInsuredProportion);
    event LiquidationInsured(bytes12 indexed vaultId, uint256 artInsured, uint256 baseInsured);
}

interface IContangoWitch is IContangoWitchEvents {
    function setInsuranceLine(bytes6 ilkId, bytes6 baseId, uint32 duration, uint64 maxInsuredProportion) external;
}
