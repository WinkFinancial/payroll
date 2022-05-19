import {SignerWithAddress} from '@nomiclabs/hardhat-ethers/signers';
import {ethers} from 'hardhat';
import {expect} from 'chai';
import {Contract, BigNumber} from 'ethers';
import {deploy, DeployResult} from './helpers/uniswap';

import {Token, Payroll} from '../typechain-types';
import {PaymentStruct} from '../typechain-types/Payroll';
import {network} from 'hardhat';

let uniswapV2Router02: Contract;
let tokenA: Token;
let tokenB: Token;
let tokenC: Token;
let payroll: Payroll;
let admin: SignerWithAddress;
let payer: SignerWithAddress;
let userA: SignerWithAddress;
let userB: SignerWithAddress;
let feeAddress: SignerWithAddress;

describe('Contract: Payroll', () => {
  beforeEach(async () => {
    await network.provider.request({
      method: 'hardhat_reset',
    });
    [admin, payer, userA, userB, feeAddress] = await ethers.getSigners();

    const Token = await ethers.getContractFactory('Token');
    tokenA = (await Token.deploy('Token_A', 'TKA')) as Token;
    tokenB = (await Token.deploy('Token_B', 'TKB')) as Token;
    tokenC = (await Token.deploy('Token_C', 'TKC')) as Token;

    if (Number(tokenA.address) > Number(tokenB.address)) {
      const tmp = tokenB;
      tokenB = tokenA;
      tokenA = tmp;
    }

    if (Number(tokenB.address) > Number(tokenC.address)) {
      const tmp = tokenC;
      tokenC = tokenB;
      tokenB = tmp;
    }

    const deployResult: DeployResult = await deploy({owner: admin});
    uniswapV2Router02 = deployResult.uniswapV2Router02;

    const Payroll = await ethers.getContractFactory('Payroll');
    payroll = (await Payroll.deploy()) as Payroll;
    await payroll.initialize(uniswapV2Router02.address, true, feeAddress.address, 0);

    await tokenB.transfer(payer.address, 1000000);
  });

  describe('SwapRouter', () => {
    it('should update swapRouter', async () => {
      const newRouter = ethers.Wallet.createRandom();
      await payroll.setSwapRouter(newRouter.address, true);
      expect(await payroll.isSwapV2()).to.be.true;
    });

    it('should not update swapRouter with a zero address', async () => {
      await expect(payroll.setSwapRouter(ethers.constants.AddressZero, true)).to.be.revertedWith(
        'Payroll: Cannot set a 0 address as swapRouter'
      );
    });

    it('should not initialize swapRouter with a zero address', async () => {
      const PayrollTest = await ethers.getContractFactory('Payroll');
      const payrollTest: Payroll = (await PayrollTest.deploy()) as Payroll;
      await expect(
        payrollTest.initialize(ethers.constants.AddressZero, false, feeAddress.address, 0)
      ).to.be.revertedWith('Payroll: Cannot set a 0 address as swapRouter');
    });
  });

  describe('Fees', () => {
    it('Should set feeAddress', async () => {
      await payroll.setFeeAddress(userA.address);
      expect(await payroll.feeAddress()).to.be.equal(userA.address);
    });

    it('should not set feeAddress with a zero address', async () => {
      await expect(payroll.setFeeAddress(ethers.constants.AddressZero)).to.be.revertedWith(
        `Payroll: Fee address can't be 0`
      );
    });

    it('Only owner can set feeAddress', async () => {
      await expect(payroll.connect(userA).setFeeAddress(userA.address)).to.be.revertedWith(
        `Ownable: caller is not the owner`
      );
    });

    it('Should set fee', async () => {
      const fee = BigNumber.from(100000);
      await payroll.setFee(fee);
      expect(await payroll.fee()).to.be.equal(fee);
    });

    it('should not set fee bigger or equal to 3%', async () => {
      const fee = ethers.utils.parseUnits('0.03', 'ether');
      await expect(payroll.setFee(fee)).to.be.revertedWith(`Payroll: Fee should be less than 3%`);
    });

    it('Only owner can set fee', async () => {
      await expect(payroll.connect(userA).setFee(0)).to.be.revertedWith(`Ownable: caller is not the owner`);
    });
  });

  describe('performMultiPayment', () => {
    beforeEach(async () => {
      await tokenB.connect(payer).approve(payroll.address, 1000000);
      await tokenA.connect(payer).approve(payroll.address, 1000000);
      await tokenC.connect(payer).approve(payroll.address, 1000000);
      await payroll.approveTokens([tokenA.address, tokenB.address, tokenC.address]);
    });

    it('should performMultiPayment transfer', async () => {
      const payments: PaymentStruct[] = [
        {
          token: tokenB.address,
          receivers: [userA.address, userB.address],
          amountsToTransfer: [50, 50],
        },
      ];

      await payroll.connect(payer).performMultiPayment(payments);

      expect(await tokenB.balanceOf(userA.address)).to.equal(50);
      expect(await tokenB.balanceOf(userB.address)).to.equal(50);
    });

    it('should revert if empty amounts', async () => {
      const payments: PaymentStruct[] = [
        {
          token: tokenB.address,
          receivers: [userA.address, userB.address],
          amountsToTransfer: [],
        },
      ];

      await expect(payroll.connect(payer).performMultiPayment(payments)).to.be.revertedWith(
        'Payroll: No amounts to transfer'
      );
    });

    it('should revert because amountsToTransfers and receivers length', async () => {
      const payments: PaymentStruct[] = [
        {
          token: tokenB.address,
          receivers: [userA.address, userB.address],
          amountsToTransfer: [50, 50, 50],
        },
      ];

      await expect(payroll.connect(payer).performMultiPayment(payments)).to.be.revertedWith(
        'Payroll: Arrays must have same length'
      );
    });

    it('should revert because token address is zero', async () => {
      const payments: PaymentStruct[] = [
        {
          token: ethers.constants.AddressZero,
          receivers: [userA.address, userB.address],
          amountsToTransfer: [50, 50],
        },
      ];

      await expect(payroll.connect(payer).performMultiPayment(payments)).to.be.revertedWith(
        'Payroll: Token is 0 address'
      );
    });

    it('should revert because one receiver is a zero address', async () => {
      const payments: PaymentStruct[] = [
        {
          token: tokenB.address,
          receivers: [userA.address, ethers.constants.AddressZero],
          amountsToTransfer: [50, 50],
        },
      ];

      await expect(payroll.connect(payer).performMultiPayment(payments)).to.be.revertedWith(
        'Payroll: Cannot send to a 0 address'
      );
    });
  });
});