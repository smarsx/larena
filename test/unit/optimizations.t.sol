// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";
import {GasHelpers} from "../utils/GasHelper.t.sol";
import {MemoryPlus} from "../utils/Memory.sol";
import {Larena} from "../../src/Larena.sol";

contract OptimizationsTest is Test, GasHelpers, MemoryPlus {
    uint256 public constant EPOCH_LENGTH = 30 days;
    uint256 public constant SLOT = 34;
    address $xaddr = address(0x77);
    address $addr = address(0x77);
    uint56 $prevTokenID = 100;
    uint32 $start = 0;
    uint8 $allowRecovery = 1;

    function testMultiple(uint256 id) public pure {
        // set emission multiple
        uint256 multiple = 9; // beyond 10000

        // The branchless expression below is equivalent to:
        //      if (id <= 3054) multiple = 5;
        // else if (id <= 5672) multiple = 6;
        // else if (id <= 7963) multiple = 7;
        // else if (id <= 10000) multiple = 8;
        assembly {
            // prettier-ignore
            multiple := sub(sub(sub(sub(
                multiple,
                lt(id, 10001)),
                lt(id, 7964)),
                lt(id, 5673)),
                lt(id, 3055)
            )
        }

        uint256 multipleBranched = 9;

        if (id <= 3054) multipleBranched = 5;
        else if (id <= 5672) multipleBranched = 6;
        else if (id <= 7963) multipleBranched = 7;
        else if (id <= 10000) multipleBranched = 8;

        assertEq(multiple, multipleBranched);
    }

    function testUtilization(uint8 hrs) public pure {
        uint256 util;
        uint256 utilBranched;

        assembly {
            util := 20
            // prettier-ignore
            switch div(hrs, 6)
                case 0 { util := 95 }
                case 1 { util := 90 }
                case 2 { util := 80 }
                case 3 { util := 65 }
                case 4 { util := 45 }
        }

        if (hrs < 6) utilBranched = 95;
        else if (hrs < 12) utilBranched = 90;
        else if (hrs < 18) utilBranched = 80;
        else if (hrs < 24) utilBranched = 65;
        else if (hrs < 30) utilBranched = 45;
        else utilBranched = 20;

        assertEq(util, utilBranched);
    }

    function testVariousBitMasking(uint8 z) public view brutalizeMemory {
        uint8 idx = uint8(z % 3);
        uint8 idx2 = idx % 2 == 0 ? uint8(1) : uint8(2);

        // read
        uint8 a;
        uint8 b;
        uint8 c;
        uint8 aa;
        uint8 bb;
        uint8 cc;
        c = uint8(z & (1 << uint8(idx)));
        b = uint8(z & (1 << uint8(Larena.ClaimType(idx))));
        assembly {
            a := and(z, shl(and(idx, 0xff), 1))
        }
        cc = uint8(z & (1 << uint8(idx2)));
        bb = uint8(z & (1 << uint8(Larena.ClaimType(idx2))));
        assembly {
            aa := and(z, shl(and(idx2, 0xff), 1))
        }
        assertEq(a, b);
        assertEq(b, c);
        assertEq(aa, bb);
        assertEq(bb, cc);

        // write
        if (a == 0) {
            z = uint8(z | (1 << uint8(Larena.ClaimType(idx))));

            c = uint8(z & (1 << uint8(idx)));
            b = uint8(z & (1 << uint8(Larena.ClaimType(idx))));
            assembly {
                a := and(z, shl(and(idx, 0xff), 1))
            }

            cc = uint8(z & (1 << uint8(idx2)));
            bb = uint8(z & (1 << uint8(Larena.ClaimType(idx2))));
            assembly {
                aa := and(z, shl(and(idx2, 0xff), 1))
            }
            assertEq(a, b);
            assertEq(b, c);
            assertEq(aa, bb);
            assertEq(bb, cc);
        }
    }

    function testDzCondition(uint256 _dz, uint48 _warp) public brutalizeMemory {
        vm.warp(_warp);

        uint256 c;
        uint256 cc;

        if (_dz > 0 && block.timestamp > _dz) {
            c = 1;
        } else {
            c = 0;
        }

        assembly {
            cc := and(gt(_dz, 0), gt(timestamp(), _dz))
        }

        assertEq(c, cc);
    }

    // invalidations that I removed from the muldiv in FixedPointMathLib
    function testMulDivInval(uint128 _coin, uint8 _penalty) public pure {
        vm.assume(_penalty >= 20 && _penalty <= 95);
        assertTrue(_coin <= type(uint256).max / _penalty);
    }

    function testMulDivInvalShares(uint128 _coin, uint8 _share) public pure {
        vm.assume(_share > 1 && _share <= 85);
        assertTrue(_coin <= type(uint256).max / _share);
    }

    function testStart() public brutalizeMemory {
        $allowRecovery = 1;

        uint256 start;
        assembly {
            start := and(shr(216, sload(SLOT)), 0xffffffff)
        }
        assertEq(start, 0);
    }

    function testWrite(uint32 x) public brutalizeMemory {
        $start = x;
        uint32 start;
        assembly {
            start := and(shr(216, sload(SLOT)), 0xffffffff)
        }
        assertEq(start, x);
        assertEq(start, $start);
    }
}
