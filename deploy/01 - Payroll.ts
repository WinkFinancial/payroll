import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import {networksByChainId} from '@wink-financial/wink-assets';

const version = 'v0.2.0';
const contractName = 'Payroll';

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  async function main() {
    // Hardhat always runs the compile task when running scripts with its command
    // line interface.
    //
    // If this script is run directly using `node` you may want to call compile
    // manually to make sure everything is compiled
    // await hre.run('compile');

    console.log(`Deploying ${contractName} ${version}`);
    const {deployments, getNamedAccounts, network} = hre;
    const chainId = network.config.chainId || 0;

    const networkData = networksByChainId[chainId];

    const {deploy} = deployments;

    const {deployer, feeAddress, swapRouter, isSwapRouterV2} = await getNamedAccounts();

    const routerAddress = networkData?.routerAddress || swapRouter;
    const isSwapV2 = networkData?.isSwapV2 || isSwapRouterV2;
    const fee = 0;

    const deployResult = await deploy(contractName, {
      from: deployer,
      proxy: {
        proxyContract: 'OpenZeppelinTransparentProxy',
        execute: {
          init: {
            methodName: 'initialize',
            args: [routerAddress, isSwapV2, feeAddress, fee],
          },
        },
      },
      gasLimit: 4000000,
      log: true,
    });

    if (deployResult.newlyDeployed && deployResult.transactionHash && network.live) {
      const blocks = 5;
      console.log(`Waiting ${blocks} blocks before verifying`);
      await hre.ethers.provider.waitForTransaction(deployResult.transactionHash, blocks);
      try {
        console.log(`Startig Verification of Payroll_Implementation ${deployResult.implementation}`);
        await hre.run('verify:verify', {
          address: deployResult.implementation,
        });
      } catch (err: any) {
        if (err.message.includes('Already Verified')) {
          return;
        }
        throw err;
      }
    }

    return true;
  }

  // We recommend this pattern to be able to use async/await everywhere
  // and properly handle errors.
  await main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
};

const id = contractName + version;

export default func;
func.tags = [contractName, version, 'upgrade'];
func.id = id;
