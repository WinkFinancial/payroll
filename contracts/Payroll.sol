//SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IERC20Basic.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

/**
 * @title A contract that allows multiple payments in one transaction
 * @author Lucas Marc
 */
contract Payroll is Initializable, AccessControl {
    bytes32 public constant PAYER_ROLE = keccak256("PAYER_ROLE");
    bytes32 public constant ADMIN_ROLE = 0x00;

    ISwapRouter public swapRouter;

    address public owner;

    struct Payment {
        address token;
        address[] receivers;
        uint256[] amountsToTransfer;
    }

    struct Swap {
        address token;
        uint256 amountOut;
        uint256 amountInMax;
        uint24 poolFee;
    }

    function initialize(address _owner, address _swapRouter)
        public
        initializer
    {
        owner = _owner;
        _setupRole(ADMIN_ROLE, _owner);
        _setupRole(PAYER_ROLE, _owner);
        swapRouter = ISwapRouter(_swapRouter);
    }

    event BatchPaymentFinished(
        address[] _receivers,
        uint256[] _amountsToTransfer
    );

    event SwapFinished(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountReceived
    );

    /**
     * Perform the swap and then the payment to the given addresses
     * @param _erc20TokenOrigin ERC20 token address to swap for another
     * @param _totalAmountToSwap Total amount of erc20TokenOrigin to spend in swaps
     * @param _deadline The unix timestamp after a swap will fail
     * @param _swaps The array of the Swaps data
     * @param _payments The array of the Payment data
     * @notice Currently the function only works with ERC20 tokens
     */
    function performSwapAndPayment(
        address _erc20TokenOrigin,
        uint256 _totalAmountToSwap,
        uint32 _deadline,
        Swap[] calldata _swaps,
        Payment[] calldata _payments
    ) external onlyRole(PAYER_ROLE) {
        performSwap(_erc20TokenOrigin, _totalAmountToSwap, _deadline, _swaps);

        for (uint256 i = 0; i < _payments.length; i++) {
            performPayment(
                _payments[i].token,
                _payments[i].receivers,
                _payments[i].amountsToTransfer
            );
        }
    }

    /**
     * Perform the swap to the given addresses and amounts
     * @param _erc20TokenOrigin ERC20 token address to swap for another
     * @param _totalAmountToSwap Total amount of erc20TokenOrigin to spend in swaps
     * @param _deadline The unix timestamp after a swap will fail
     * @param _swaps The array of the Swaps data
     * @notice Currently the function only works with ERC20 tokens
     */
    function performSwap(
        address _erc20TokenOrigin,
        uint256 _totalAmountToSwap,
        uint32 _deadline,
        Swap[] calldata _swaps
    ) internal {
        TransferHelper.safeTransferFrom(
            _erc20TokenOrigin,
            msg.sender,
            address(this),
            _totalAmountToSwap
        );

        TransferHelper.safeApprove(
            _erc20TokenOrigin,
            address(swapRouter),
            _totalAmountToSwap
        );

        for (uint256 i = 0; i < _swaps.length; i++) {
            swapExactOutputSingle(
                _erc20TokenOrigin,
                _swaps[i].token,
                _swaps[i].poolFee,
                _swaps[i].amountOut,
                _swaps[i].amountInMax,
                _deadline
            );
        }

        IERC20Basic erc20token = IERC20Basic(_erc20TokenOrigin);

        TransferHelper.safeTransfer(
            _erc20TokenOrigin,
            msg.sender,
            erc20token.balanceOf(address(this))
        );

        TransferHelper.safeApprove(_erc20TokenOrigin, address(swapRouter), 0);
    }

    /**
     * Perform ERC20 tokens swap
     * @param _tokenIn ERC20 token address to swap for another
     * @param _tokenOut ERC20 token address to receive
     * @param _poolFee Pool fee tokenIn/tokenOut
     * @param _amountOut Exact amount of tokenOut to receive
     * @param _amountInMax Max amount of tokenIn to pay
     * @param _deadline The unix timestamp after a swap will fail
     * @notice Currently the function only works with ERC20 tokens
     * @notice Currently the function only works with single pools tokenIn/tokenOut
     */
    function swapExactOutputSingle(
        address _tokenIn,
        address _tokenOut,
        uint24 _poolFee,
        uint256 _amountOut,
        uint256 _amountInMax,
        uint32 _deadline
    ) internal returns (uint256 amountIn) {
        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter
            .ExactOutputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                fee: _poolFee,
                recipient: address(this),
                deadline: _deadline,
                amountOut: _amountOut,
                amountInMaximum: _amountInMax,
                sqrtPriceLimitX96: 0
            });

        amountIn = swapRouter.exactOutputSingle(params);

        emit SwapFinished(_tokenIn, _tokenOut, amountIn);
    }

    /**
     * Performs the payment to the given addresses
     * @param _erc20TokenAddress The address of the ERC20 token to transfer
     * @param _receivers The array of payment receivers
     * @param _amountsToTransfer The array of payments' amounts to perform. The amount will be transfered to the address on _receivers with the same index.
     * @notice Currently the function only works with only one ERC20 token
     */
    function performPayment(
        address _erc20TokenAddress,
        address[] calldata _receivers,
        uint256[] calldata _amountsToTransfer
    ) public onlyRole(PAYER_ROLE) {
        require(
            _amountsToTransfer.length == _receivers.length,
            "Both arrays must have the same length"
        );

        address currentReceiver;
        uint256 currentAmount;

        for (uint256 i = 0; i < _receivers.length; i++) {
            currentReceiver = _receivers[i];
            require(
                _receivers[i] != address(0),
                "ERC20: cannot register a 0 address"
            );
            currentAmount = _amountsToTransfer[i];
            TransferHelper.safeTransfer(
                _erc20TokenAddress,
                currentReceiver,
                currentAmount
            );
        }
        emit BatchPaymentFinished(_receivers, _amountsToTransfer);
    }
}
