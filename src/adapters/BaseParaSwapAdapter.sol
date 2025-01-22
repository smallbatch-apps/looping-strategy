// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.28;

import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

abstract contract BaseParaSwapAdapter {
    IPool public immutable POOL;

    constructor(address pool) {
        POOL = IPool(pool);
    }

    function getReserveData(
        address asset
    ) internal view returns (DataTypes.ReserveDataLegacy memory) {
        return POOL.getReserveData(asset);
    }
}
