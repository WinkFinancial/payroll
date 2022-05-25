//SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./interfaces/IERC20Basic.sol";
import "./interfaces/IUniswap.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

/**
 * @title Think and Dev Paymentbox
 * @author Think and Dev Team
 * @notice Swap and transfer multiple ERC20 pairs to multiple accounts in a single transaction.
 * Use any router address of any DEX that uses Uniswap protocol v2 or v3 to make swaps.
 */
contract Payroll is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /**
     * Returns the address of the Uniswap protocol router, it could be v2 or v3.
     */
    address public swapRouter;
    address public feeAddress;
    uint256 public fee;
    uint256 public constant MANTISSA = 1e18;

    /**
     * Returns if the contract is working with a v2 Uniswap protocol;
     * true means v2, false means v3.
     */
    bool public isSwapV2;

    struct Payment {
        address token;
        address[] receivers;
        uint256[] amountsToTransfer;
    }

    struct SwapV2 {
        uint256 amountOut;
        uint256 amountInMax;
        uint24 poolFee;
        address[] path;
    }

    struct SwapV3 {
        address token;
        uint256 amountOut;
        uint256 amountInMax;
        uint24 poolFee;
        bytes path;
    }

    event SwapRouterChanged(address _swapRouter, bool _isSwapV2);
    event FeeChanged(uint256 _fee);
    event FeeCharged(address _erc20TokenAddress, address _feeAddress, uint256 _fees);
    event FeeAddressChanged(address _feeAddress);
    event BatchPaymentFinished(address _erc20TokenAddress, address[] _receivers, uint256[] _amountsToTransfer);
    event SwapFinished(address _tokenIn, address _tokenOut, uint256 _amountReceived);

    /**
     * @param _swapRouter Router address to execute swaps.
     * @param _isSwapV2 Boolean to specify the version of the router; true means v2, false means v3.
     */
    function initialize(
        address _swapRouter,
        bool _isSwapV2,
        address _feeAddress,
        uint256 _fee
    ) public initializer {
        __ReentrancyGuard_init();
        __Ownable_init();
        _setSwapRouter(_swapRouter, _isSwapV2);
        _setFeeAddress(_feeAddress);
        _setFee(_fee);
    }

    /**
     * Set the fee that will be charged, fees are divided by mantissa
     * @param _fee Percentage that will be charged.
     */
    function setFee(uint256 _fee) external onlyOwner {
        _setFee(_fee);
    }

    function _setFee(uint256 _fee) internal {
        require(_fee < 3e16, "Payroll: Fee should be less than 3%");
        fee = _fee;
        emit FeeChanged(_fee);
    }

    /**
     * Set the address that will receive the fees.
     * @param _feeAddress Address that will receive the fees.
     */
    function setFeeAddress(address _feeAddress) external onlyOwner {
        _setFeeAddress(_feeAddress);
    }

    function _setFeeAddress(address _feeAddress) internal {
        require(_feeAddress != address(0), "Payroll: Fee address can't be 0");
        feeAddress = _feeAddress;
        emit FeeAddressChanged(_feeAddress);
    }

    /**
     * Set the SwapRouter and the version to be used.
     * @param _swapRouter Router address to execute swaps.
     * @param _isSwapV2 Boolean to specify the version of the router; true means v2, false means v3.
     */
    function setSwapRouter(address _swapRouter, bool _isSwapV2) external onlyOwner {
        _setSwapRouter(_swapRouter, _isSwapV2);
    }

    function _setSwapRouter(address _swapRouter, bool _isSwapV2) internal {
        require(_swapRouter != address(0), "Payroll: Cannot set a 0 address as swapRouter");
        isSwapV2 = _isSwapV2;
        swapRouter = _swapRouter;
        emit SwapRouterChanged(_swapRouter, _isSwapV2);
    }

    /**
     * Approves the following token to be used on swapRouter
     * @param _erc20TokenOrigin ERC20 token address to approve.
     */
    function approveTokens(address[] calldata _erc20TokenOrigin) external nonReentrant {
        for (uint256 i = 0; i < _erc20TokenOrigin.length; i++) {
            // approves the swapRouter to spend totalAmountToSpend of erc20TokenOrigin
            TransferHelper.safeApprove(_erc20TokenOrigin[i], address(swapRouter), type(uint256).max);
        }
    }

    /**
     * Perform the swap and the transfer to the given addresses.
     * @param _erc20TokenOrigin ERC20 token address to swap for another.
     * @param _totalAmountToSwap Total amount of erc20TokenOrigin to spend in swaps.
     * @param _deadline The unix timestamp after a swap will fail.
     * @param _swaps The array of the Swaps data.
     * @param _payments The array of the Payment data.
     * @notice Currently the function only works with ERC20 tokens.
     */
    function performSwapV3AndPayment(
        address _erc20TokenOrigin,
        uint256 _totalAmountToSwap,
        uint32 _deadline,
        SwapV3[] calldata _swaps,
        Payment[] calldata _payments
    ) external nonReentrant {
        require(!isSwapV2, "Payroll: Not uniswapV3");
        if (_swaps.length > 0) {
            _performSwapV3(_erc20TokenOrigin, _totalAmountToSwap, _deadline, _swaps);
        }

        _performMultiPayment(_payments);
    }


    function performSwapV3(
        address _erc20TokenOrigin,
        uint256 _totalAmountToSwap,
        uint32 _deadline,
        SwapV3[] calldata _swaps
    ) external returns(uint256) {
         require(!isSwapV2, "Payroll: Not uniswapV3");
        return _performSwapV3(_erc20TokenOrigin, _totalAmountToSwap, _deadline, _swaps);
    }

    /**
     * Perform the swap to the given token addresses and amounts.
     * @param _erc20TokenOrigin ERC20 token address to swap for another.
     * @param _totalAmountToSwap Total amount of erc20TokenOrigin to spend in swaps.
     * @param _deadline The unix timestamp after a swap will fail.
     * @param _swaps The array of the Swaps data.
     */
    function _performSwapV3(
        address _erc20TokenOrigin,
        uint256 _totalAmountToSwap,
        uint32 _deadline,
        SwapV3[] calldata _swaps
    ) internal returns(uint256) {
        // transfer the totalAmountToSpend of erc20TokenOrigin from the msg.sender to this contract
        // msg.sender must approve this contract for erc20TokenOrigin
        TransferHelper.safeTransferFrom(_erc20TokenOrigin, msg.sender, address(this), _totalAmountToSwap);

        uint256 totalAmountIn = 0;
        for (uint256 i = 0; i < _swaps.length; i++) {
            uint256 amountIn = IUniswapV3(swapRouter).exactOutput(
                IUniswapV3.ExactOutputParams({
                    path: _swaps[i].path,
                    recipient: msg.sender,
                    deadline: _deadline,
                    amountOut: _swaps[i].amountOut,
                    amountInMaximum: _swaps[i].amountInMax
                })
            );
            totalAmountIn = totalAmountIn + amountIn;
            emit SwapFinished(_erc20TokenOrigin, _swaps[i].token, amountIn);
        }

        uint256 leftOver = IERC20Basic(_erc20TokenOrigin).balanceOf(address(this));
        if (leftOver > 0) {
            // return the leftover of _erc20TokenOrigin
            TransferHelper.safeTransfer(_erc20TokenOrigin, msg.sender, leftOver);
        }
        return totalAmountIn;
    }


        /**
     * Perform the swap and the transfer to the given addresses using Uniswap V2 interface.
     * @param _erc20TokenOrigin ERC20 token address to swap for another.
     * @param _totalAmountToSwap Total amount of erc20TokenOrigin to spend in swaps.
     * @param _deadline The unix timestamp after a swap will fail.
     * @param _swaps The array of the Swaps data.
     * @param _payments The array of the Payment data.
     * @notice Currently the function only works with ERC20 tokens.
     */
    function performSwapV2AndPayment(
        address _erc20TokenOrigin,
        uint256 _totalAmountToSwap,
        uint32 _deadline,
        SwapV2[] calldata _swaps,
        Payment[] calldata _payments
    ) external nonReentrant {
        require(isSwapV2, "Payroll: Not uniswapV2");
        if (_swaps.length > 0) {
            _performSwapV2(_erc20TokenOrigin, _totalAmountToSwap, _deadline, _swaps);
        }

        _performMultiPayment(_payments);
    }

    function performSwapV2(
        address _erc20TokenOrigin,
        uint256 _totalAmountToSwap,
        uint32 _deadline,
        SwapV2[] calldata _swaps
    ) external returns(uint256) {
         require(isSwapV2, "Payroll: Not uniswapV2");
        return _performSwapV2(_erc20TokenOrigin, _totalAmountToSwap, _deadline, _swaps);
    }

    /**
     * Perform the swap to the given token addresses and amounts.
     * @param _erc20TokenOrigin ERC20 token address to swap for another.
     * @param _totalAmountToSwap Total amount of erc20TokenOrigin to spend in swaps.
     * @param _deadline The unix timestamp after a swap will fail.
     * @param _swaps The array of the Swaps data.
     */
    function _performSwapV2(
        address _erc20TokenOrigin,
        uint256 _totalAmountToSwap,
        uint32 _deadline,
        SwapV2[] calldata _swaps
    ) internal returns(uint256) {
        // transfer the totalAmountToSpend of erc20TokenOrigin from the msg.sender to this contract
        // msg.sender must approve this contract for erc20TokenOrigin
        TransferHelper.safeTransferFrom(_erc20TokenOrigin, msg.sender, address(this), _totalAmountToSwap);

        uint256 totalAmountIn = 0;
        for (uint256 i = 0; i < _swaps.length; i++) {
            require(_swaps[i].path[0] == _erc20TokenOrigin, "Payroll: Swap not token origin");
            // return the amount spend of tokenIn
            uint256 amountIn = IUniswapV2(swapRouter).swapTokensForExactTokens(_swaps[i].amountOut, _swaps[i].amountInMax, _swaps[i].path, msg.sender, _deadline)[
                0
            ];
            totalAmountIn = totalAmountIn + amountIn;
            emit SwapFinished(_erc20TokenOrigin, _swaps[i].path[_swaps.length-1], amountIn);
        }

        uint256 leftOver = IERC20Basic(_erc20TokenOrigin).balanceOf(address(this));
        if (leftOver > 0) {
            // return the leftover of _erc20TokenOrigin
            TransferHelper.safeTransfer(_erc20TokenOrigin, msg.sender, leftOver);
        }
        return totalAmountIn;
    }



    /**
     * Perform the payments to the given addresses and amounts, public method.
     * @param _payments The array of the Payment data.
     */
    function performMultiPayment(Payment[] calldata _payments) external nonReentrant {
        _performMultiPayment(_payments);
    }

    /**
     * Perform the payments to the given addresses and amounts, internal method.
     * @param _payments The array of the Payment data.
     */
    function _performMultiPayment(Payment[] calldata _payments) internal {
        for (uint256 i = 0; i < _payments.length; i++) {
            _performPayment(_payments[i].token, _payments[i].receivers, _payments[i].amountsToTransfer);
        }
    }

    /**
     * Performs the payment to the given addresses.
     * @param _erc20TokenAddress The address of the ERC20 token to transfer.
     * @param _receivers The array of payment receivers.
     * @param _amountsToTransfer The array of payments' amounts to perform.
     * The amount will be transfered to the address on _receivers with the same index.
     */
    function _performPayment(
        address _erc20TokenAddress,
        address[] calldata _receivers,
        uint256[] calldata _amountsToTransfer
    ) internal {
        require(_erc20TokenAddress != address(0), "Payroll: Token is 0 address");
        require(_amountsToTransfer.length > 0, "Payroll: No amounts to transfer");
        require(_amountsToTransfer.length == _receivers.length, "Payroll: Arrays must have same length");

        uint256 acumulatedFee = 0;
        for (uint256 i = 0; i < _receivers.length; i++) {
            require(_receivers[i] != address(0), "Payroll: Cannot send to a 0 address");
            acumulatedFee = acumulatedFee + (_amountsToTransfer[i] * fee) / MANTISSA;
            TransferHelper.safeTransferFrom(_erc20TokenAddress, msg.sender, _receivers[i], _amountsToTransfer[i]);
        }
        emit BatchPaymentFinished(_erc20TokenAddress, _receivers, _amountsToTransfer);
        if (acumulatedFee > 0) {
            TransferHelper.safeTransferFrom(_erc20TokenAddress, msg.sender, feeAddress, acumulatedFee);
        }
        emit FeeCharged(_erc20TokenAddress, feeAddress, acumulatedFee);
    }
}
