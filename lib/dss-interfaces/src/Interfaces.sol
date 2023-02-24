// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.5.12;

import { GemAbstract } from "./ERC/GemAbstract.sol";

import { DSAuthorityAbstract, DSAuthAbstract } from "./dapp/DSAuthorityAbstract.sol";
import { DSChiefAbstract } from "./dapp/DSChiefAbstract.sol";
import { DSPauseAbstract } from "./dapp/DSPauseAbstract.sol";
import { DSPauseProxyAbstract } from "./dapp/DSPauseProxyAbstract.sol";
import { DSRolesAbstract } from "./dapp/DSRolesAbstract.sol";
import { DSSpellAbstract } from "./dapp/DSSpellAbstract.sol";
import { DSRuneAbstract } from "./dapp/DSRuneAbstract.sol";
import { DSThingAbstract } from "./dapp/DSThingAbstract.sol";
import { DSTokenAbstract } from "./dapp/DSTokenAbstract.sol";
import { DSValueAbstract } from "./dapp/DSValueAbstract.sol";

import { AuthGemJoinAbstract } from "./dss/AuthGemJoinAbstract.sol";
import { CatAbstract } from "./dss/CatAbstract.sol";
import { ChainlogAbstract } from "./dss/ChainlogAbstract.sol";
import { ChainlogHelper } from "./dss/ChainlogAbstract.sol";
import { ClipAbstract } from "./dss/ClipAbstract.sol";
import { ClipperMomAbstract } from "./dss/ClipperMomAbstract.sol";
import { CureAbstract } from "./dss/CureAbstract.sol";
import { DaiAbstract } from "./dss/DaiAbstract.sol";
import { DaiJoinAbstract } from "./dss/DaiJoinAbstract.sol";
import { DogAbstract } from "./dss/DogAbstract.sol";
import { DssAutoLineAbstract } from "./dss/DssAutoLineAbstract.sol";
import { DssCdpManagerAbstract } from "./dss/DssCdpManager.sol";
import { EndAbstract } from "./dss/EndAbstract.sol";
import { ESMAbstract } from "./dss/ESMAbstract.sol";
import { ETHJoinAbstract } from "./dss/ETHJoinAbstract.sol";
import { ExponentialDecreaseAbstract } from "./dss/ExponentialDecreaseAbstract.sol";
import { FaucetAbstract } from "./dss/FaucetAbstract.sol";
import { FlapAbstract } from "./dss/FlapAbstract.sol";
import { FlashAbstract } from "./dss/FlashAbstract.sol";
import { FlipAbstract } from "./dss/FlipAbstract.sol";
import { FlipperMomAbstract } from "./dss/FlipperMomAbstract.sol";
import { FlopAbstract } from "./dss/FlopAbstract.sol";
import { GemJoinAbstract } from "./dss/GemJoinAbstract.sol";
import { GemJoinImplementationAbstract } from "./dss/GemJoinImplementationAbstract.sol";
import { GemJoinManagedAbstract } from "./dss/GemJoinManagedAbstract.sol";
import { GetCdpsAbstract } from "./dss/GetCdpsAbstract.sol";
import { IlkRegistryAbstract } from "./dss/IlkRegistryAbstract.sol";
import { JugAbstract } from "./dss/JugAbstract.sol";
import { LerpAbstract } from "./dss/LerpAbstract.sol";
import { LerpFactoryAbstract } from "./dss/LerpFactoryAbstract.sol";
import { LinearDecreaseAbstract } from "./dss/LinearDecreaseAbstract.sol";
import { LPOsmAbstract } from "./dss/LPOsmAbstract.sol";
import { MkrAuthorityAbstract } from "./dss/MkrAuthorityAbstract.sol";
import { MedianAbstract } from "./dss/MedianAbstract.sol";
import { OsmAbstract } from "./dss/OsmAbstract.sol";
import { OsmMomAbstract } from "./dss/OsmMomAbstract.sol";
import { PotAbstract } from "./dss/PotAbstract.sol";
import { PsmAbstract } from "./dss/PsmAbstract.sol";
import { SpotAbstract } from "./dss/SpotAbstract.sol";
import { StairstepExponentialDecreaseAbstract } from "./dss/StairstepExponentialDecreaseAbstract.sol";
import { VatAbstract } from "./dss/VatAbstract.sol";
import { VestAbstract } from "./dss/VestAbstract.sol";
import { VowAbstract } from "./dss/VowAbstract.sol";

// MIP21 Abstracts
import {
  RwaInputConduitBaseAbstract,
  RwaInputConduitAbstract,
  RwaInputConduit2Abstract,
  RwaInputConduit3Abstract
} from "./dss/mip21/RwaInputConduitAbstract.sol";
import { RwaJarAbstract } from "./dss/mip21/RwaJarAbstract.sol";
import { RwaLiquidationOracleAbstract } from "./dss/mip21/RwaLiquidationOracleAbstract.sol";
import {
  RwaOutputConduitBaseAbstract,
  RwaOutputConduitAbstract,
  RwaOutputConduit2Abstract,
  RwaOutputConduit3Abstract
} from "./dss/mip21/RwaOutputConduitAbstract.sol";
import { RwaUrnAbstract } from "./dss/mip21/RwaUrnAbstract.sol";

import { GemPitAbstract } from "./sai/GemPitAbstract.sol";
import { SaiMomAbstract } from "./sai/SaiMomAbstract.sol";
import { SaiTapAbstract } from "./sai/SaiTapAbstract.sol";
import { SaiTopAbstract } from "./sai/SaiTopAbstract.sol";
import { SaiTubAbstract } from "./sai/SaiTubAbstract.sol";
import { SaiVoxAbstract } from "./sai/SaiVoxAbstract.sol";

// Partial DSS Abstracts
import { WardsAbstract } from "./utils/WardsAbstract.sol";
