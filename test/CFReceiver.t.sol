// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CFReceiver} from "../src/CFReceiver.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Test} from "lib/forge-std/src/Test.sol";

contract CFReceiverTest is Test {
    address internal immutable USER = makeAddr("User");
    address public owner = makeAddr("owner");

    CFReceiver public receiver;

    address public constant cfVault = address(0xF5e10380213880111522dd0efD3dbb45b9f62Bcc);
    address public constant spokePool = address(0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5);

    address internal immutable USDC = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address internal immutable WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function setUp() public {
        vm.prank(owner);
        receiver = new CFReceiver(cfVault, spokePool);
    }

    function testCfReceiveEth() public {
        uint32 srcChain = 1;
        uint256 inputAmount = 1 ether;
        address arbWeth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
        int256 relayFeePercentage = 123236000000000;

        bytes memory message = abi.encode(
            USER, // depositor
            USER, // recipient
            WETH, // inputToken
            arbWeth, // ARB WETH
            42161, // destinationChainId
            address(0), // exclusiveRelayer
            uint32(block.timestamp), // quoteTimestamp
            uint32(block.timestamp + 3600), // fillDeadline
            0, // exclusivityDeadline
            hex"", // depositMessage
            relayFeePercentage // relayFeePercentage
        );

        uint256 spokePoolBalanceBefore = IERC20(WETH).balanceOf(spokePool);

        // Send ETH with the call since we're using native token
        vm.deal(address(receiver), inputAmount);

        vm.prank(cfVault);
        receiver.cfReceive{value: inputAmount}(srcChain, abi.encode(USER), message, NATIVE_TOKEN, inputAmount);

        assertEq(IERC20(WETH).balanceOf(spokePool), spokePoolBalanceBefore + inputAmount);
        assertEq(USER.balance, 0);
    }

    function testCfReceiveUsdc() public {
        uint32 srcChain = 1;
        uint256 inputAmount = 50e6;
        address arbUSDC = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
        int256 relayFeePercentage = 123236000000000;

        bytes memory message = abi.encode(
            USER, // depositor
            USER, // recipient
            address(USDC), // inputToken
            arbUSDC, // outputToken
            42161, // destinationChainId
            address(0), // exclusiveRelayer
            uint32(block.timestamp), // quoteTimestamp
            uint32(block.timestamp + 3600), // fillDeadline
            0, // exclusivityDeadline
            hex"", // depositMessage
            relayFeePercentage // relayFeePercentage
        );

        // Send USDC with the call since we're using ERC20
        deal(address(USDC), address(receiver), inputAmount);

        uint256 spokePoolBalanceBefore = IERC20(address(USDC)).balanceOf(spokePool);

        vm.prank(cfVault);

        receiver.cfReceive{value: 0}(srcChain, abi.encode(USER), message, address(USDC), inputAmount);

        assertEq(IERC20(address(USDC)).balanceOf(spokePool), spokePoolBalanceBefore + inputAmount);
        assertEq(IERC20(address(USDC)).balanceOf(address(receiver)), 0);
    }
}
