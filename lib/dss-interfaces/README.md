Provides programmatic interfaces for the Dai Stablecoin System core contracts.

Import individual contracts

```solidity
import { VatAbstract } from "dss-interfaces/dss/VatAbstract.sol";
```

Import all DSS abstract contracts (best used in tests)

```solidity
import "dss-interfaces/Interfaces.sol";
```


## Example Usage


```solidity
// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.5.12;

import { VatAbstract } from "dss-interfaces/dss/VatAbstract.sol";

contract Testerface {

    VatAbstract _vat;

    constructor() public {
        _vat = VatAbstract(0xbA987bDB501d131f766fEe8180Da5d81b34b69d9);
    }

    function viewDebt() public view returns (uint256) {
        return _vat.debt();
    }
}
```

## Package Update

Update the `version` field in `package.json` and from the command line run:

```bash
> npm login
> npm publish
```

The published package will include all the files inside `src`.
