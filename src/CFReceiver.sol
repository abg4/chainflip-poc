// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ICFReceiver} from "./interfaces/ICFReceiver.sol";
import {V3SpokePoolInterface} from "lib/contracts/contracts/interfaces/V3SpokePoolInterface.sol";
import {Address} from "lib/openzeppelin-contracts/contracts/utils/Address.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title    CFReceiver
 * @dev      This contract is the base implementation for a smart contract
 *           capable of receiving cross-chain swaps and calls from the Chainflip Protocol.
 *           It has a check to ensure that the functions can only be called by one
 *           address, which should be the Chainflip Protocol. This way it is ensured that
 *           the receiver will be sent the amount of tokens passed as parameters and
 *           that the cross-chain call originates from the srcChain and address specified.
 *           This contract should be inherited and then user's logic should be implemented
 *           as the internal functions (_cfReceive and _cfReceivexCall).
 *           Remember that anyone on the source chain can use the Chainflip Protocol
 *           to make a cross-chain call to this contract. If that is not desired, an extra
 *           check on the source address and source chain should be performed.
 */
contract CFReceiver is ICFReceiver {
    using Address for address payable;

    /// @dev The address used to indicate whether the funds received are native tokens or ERC20 token
    address private constant _NATIVE_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    error NotCFVault();
    error NotOwner();

    address public cfVault;
    address public owner;
    V3SpokePoolInterface public spokePool;

    event CFReceived(uint32 indexed srcChain, bytes srcAddress, address indexed token, uint256 amount);
    event DrainedTokens(address indexed recipient, address indexed token, uint256 indexed amount);

    constructor(address _cfVault, address _spokePool) {
        owner = msg.sender;

        cfVault = _cfVault;
        spokePool = V3SpokePoolInterface(_spokePool);
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                   CF Vault calls                         //
    //                                                          //
    //////////////////////////////////////////////////////////////

    /**
     * @notice  Receiver of a cross-chain swap and call made by the Chainflip Protocol.
     *
     * @param srcChain      The source chain according to the Chainflip Protocol's nomenclature.
     * @param srcAddress    Bytes containing the source address on the source chain.
     * @param message       The message sent on the source chain. This is a general purpose message.
     * @param token         Address of the token received. _NATIVE_ADDR if it's native tokens.
     * @param amount        Amount of tokens received. This will match msg.value for native tokens.
     */
    function cfReceive(
        uint32 srcChain,
        bytes calldata srcAddress,
        bytes calldata message,
        address token,
        uint256 amount
    ) external payable override onlyCfVault {
        _cfReceive(srcChain, srcAddress, message, token, amount);
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                   Across logic                           //
    //                                                          //
    //////////////////////////////////////////////////////////////

    function _cfReceive(
        uint32 srcChain,
        bytes calldata srcAddress,
        bytes calldata message,
        address token,
        uint256 amount
    ) internal {
        emit CFReceived(srcChain, srcAddress, token, amount);

        (
            address depositor,
            address recipient,
            address inputToken,
            address outputToken,
            uint256 destinationChainId,
            address exclusiveRelayer,
            uint32 quoteTimestamp,
            uint32 fillDeadline,
            uint32 exclusivityDeadline,
            bytes memory depositMessage,
            int256 relayFeePercentage,
        ) = abi.decode(
            message,
            (address, address, address, address, uint256, address, uint32, uint32, uint32, bytes, int256, address)
        );

        uint256 outputAmount = _computeAmountPostFees(amount, relayFeePercentage);

        if (token != _NATIVE_ADDR) {
            SafeERC20.forceApprove(IERC20(inputToken), address(spokePool), type(uint256).max);
        }

        spokePool.depositV3{value: token == _NATIVE_ADDR ? amount : 0}(
            depositor,
            recipient,
            inputToken,
            outputToken,
            amount,
            outputAmount,
            destinationChainId,
            exclusiveRelayer,
            quoteTimestamp,
            fillDeadline,
            exclusivityDeadline,
            depositMessage
        );

        if (token != _NATIVE_ADDR) {
            SafeERC20.forceApprove(IERC20(inputToken), address(spokePool), 0);
        }

        _drainRemainingTokens(inputToken, payable(recipient));
    }

    function _drainRemainingTokens(address token, address payable destination) internal {
        if (token != _NATIVE_ADDR) {
            uint256 amount = IERC20(token).balanceOf(address(this));
            if (amount > 0) {
                IERC20(token).transfer(destination, amount);
                emit DrainedTokens(destination, token, amount);
            }
        } else {
            uint256 amount = address(this).balance;
            destination.sendValue(amount);
        }
    }

    function _computeAmountPostFees(uint256 amount, int256 relayFeePercentage) private pure returns (uint256) {
        return (amount * uint256(int256(1e18) - relayFeePercentage)) / 1e18;
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                 Update addresses                     //
    //                                                          //
    //////////////////////////////////////////////////////////////

    /**
     * @notice           Update Chanflip's Vault address.
     * @param _cfVault    New Chainflip's Vault address.
     */
    function updateCfVault(address _cfVault) external onlyOwner {
        cfVault = _cfVault;
    }

    /**
     * @notice           Update Across's Spoke Pool address.
     * @param _spokePool    New Across's Spoke Pool address.
     */
    function updateSpokePool(address _spokePool) external onlyOwner {
        spokePool = V3SpokePoolInterface(_spokePool);
    }

    //////////////////////////////////////////////////////////////
    //                                                          //
    //                          Modifiers                       //
    //                                                          //
    //////////////////////////////////////////////////////////////

    /// @dev Check that the sender is the Chainflip's Vault.
    modifier onlyCfVault() {
        if (msg.sender != cfVault) revert NotCFVault();
        _;
    }

    /// @dev Check that the sender is the owner.
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }
}
