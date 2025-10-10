import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import {
  MockLeveragedStrategy,
  MockERC20,
  PriceOracle,
  MockPendleOracle,
  MockAggregatorV3,
} from "../typechain-types";

// Type for strategy commands
interface Command {
  cmdType: number;
  data: string;
}

describe("LeveragedStrategy", function () {
  let owner: SignerWithAddress;
  let parent: SignerWithAddress;
  let user: SignerWithAddress;
  let strategy: MockLeveragedStrategy;
  let baseAsset: MockERC20;
  let priceOracle: PriceOracle;
  let pendleOracle: MockPendleOracle;
  let baseAssetFeed: MockAggregatorV3;
  const SUPPLY = 0;
  const BORROW = 2;
  const SWAP = 4;

  const BASE_ASSET_DECIMALS = 6;
  const ORACLE_DECIMALS = 8;

  beforeEach(async function () {
    [owner, parent, user] = await ethers.getSigners();

    // Deploy base asset (USDC)
    const MockERC20Factory = await ethers.getContractFactory("MockERC20");
    const initialSupply = ethers.parseUnits("1000000", BASE_ASSET_DECIMALS);
    baseAsset = await MockERC20Factory.deploy(
      "USD Coin",
      "USDC",
      BASE_ASSET_DECIMALS,
      initialSupply
    );

    // Deploy mock price feed
    const MockAggregatorFactory = await ethers.getContractFactory("MockAggregatorV3");
    baseAssetFeed = await MockAggregatorFactory.deploy(ORACLE_DECIMALS);
    await baseAssetFeed.updateAnswer(1_00_000_000); // $1.00

    // Deploy Pendle Oracle mock
    const MockPendleOracleFactory = await ethers.getContractFactory("MockPendleOracle");
    pendleOracle = await MockPendleOracleFactory.deploy();

    // Deploy PriceOracle
    const PriceOracleFactory = await ethers.getContractFactory("PriceOracle");
    priceOracle = await PriceOracleFactory.deploy(await pendleOracle.getAddress());
    await priceOracle.addPriceFeed(await baseAsset.getAddress(), await baseAssetFeed.getAddress());

    // Deploy MockLeveragedStrategy
    const MockStrategyFactory = await ethers.getContractFactory("MockLeveragedStrategy");
    strategy = await MockStrategyFactory.deploy(
      parent.address,
      await baseAsset.getAddress(),
      await priceOracle.getAddress()
    );
  });

  describe("Deployment", function () {
    it("Should set parent address correctly", async function () {
      expect(await strategy.parent()).to.equal(parent.address);
    });

    it("Should set base asset correctly", async function () {
      expect(await strategy.baseAsset()).to.equal(await baseAsset.getAddress());
    });

    it("Should set price oracle correctly", async function () {
      expect(await strategy.priceOracle()).to.equal(await priceOracle.getAddress());
    });

    it("Should revert if parent is zero address", async function () {
      const MockStrategyFactory = await ethers.getContractFactory("MockLeveragedStrategy");
      await expect(
        MockStrategyFactory.deploy(
          ethers.ZeroAddress,
          await baseAsset.getAddress(),
          await priceOracle.getAddress()
        )
      ).to.be.revertedWithCustomError(strategy, "InvalidToken");
    });

    it("Should revert if base asset is zero address", async function () {
      const MockStrategyFactory = await ethers.getContractFactory("MockLeveragedStrategy");
      await expect(
        MockStrategyFactory.deploy(
          parent.address,
          ethers.ZeroAddress,
          await priceOracle.getAddress()
        )
      ).to.be.revertedWithCustomError(strategy, "InvalidToken");
    });
  });

  describe("Access Control", function () {
    it("Should only allow parent to call deposit", async function () {
      const commands: Command[] = [];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      await expect(
        strategy.connect(user).deposit(
          await baseAsset.getAddress(),
          1000,
          ethers.ZeroAddress, // flashLoanToken
          0, // providedAmount
          0, // expectedAmount
          data
        )
      ).to.be.revertedWithCustomError(strategy, "Unauthorized");
    });

    it("Should only allow parent to call withdraw", async function () {
      const commands: Command[] = [];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      await expect(
        strategy.connect(user).withdraw(
          ethers.parseEther("1"), // 100%
          await baseAsset.getAddress(),
          ethers.ZeroAddress, // flashLoanToken
          0, // providedAmount
          0, // expectedAmount
          data
        )
      ).to.be.revertedWithCustomError(strategy, "Unauthorized");
    });

    it("Should only allow parent to call rebalance", async function () {
      const commands: Command[] = [];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      await expect(
        strategy.connect(user).rebalance(
          ethers.ZeroAddress, // flashLoanToken
          0, // providedAmount
          0, // expectedAmount
          data
        )
      ).to.be.revertedWithCustomError(strategy, "Unauthorized");
    });
  });

  describe("Command Execution", function () {
    it("Should execute SUPPLY command", async function () {
      const amount = 1000n * 10n ** BigInt(BASE_ASSET_DECIMALS);

      const supplyCommand = {
        cmdType: 0, // SUPPLY
        data: ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [await baseAsset.getAddress(), amount]
        ),
      };

      const commands = [supplyCommand];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      // Transfer tokens to strategy first
      await baseAsset.transfer(await strategy.getAddress(), amount);

      await strategy.connect(parent).deposit(
        await baseAsset.getAddress(),
        amount,
        ethers.ZeroAddress, // flashLoanToken
        0, // providedAmount
        0, // expectedAmount
        data
      );

      expect(await strategy.collateral(await baseAsset.getAddress())).to.equal(amount);
    });

    it("Should execute BORROW command", async function () {
      const borrowAmount = 500n * 10n ** BigInt(BASE_ASSET_DECIMALS);

      const borrowCommand = {
        cmdType: 2, // BORROW
        data: ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [await baseAsset.getAddress(), borrowAmount]
        ),
      };

      const commands = [borrowCommand];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      await strategy.connect(parent).deposit(
        await baseAsset.getAddress(),
        0,
        ethers.ZeroAddress, // flashLoanToken
        0, // providedAmount
        0, // expectedAmount
        data
      );

      expect(await strategy.debt(await baseAsset.getAddress())).to.equal(borrowAmount);
    });

    it("Should execute proportional withdraw (protocol operations)", async function () {
      const collateralAmount = 1000n * 10n ** BigInt(BASE_ASSET_DECIMALS);

      // Set up initial collateral
      await strategy.setCollateral(await baseAsset.getAddress(), collateralAmount);

      // Register token contract to enable minting on withdraw
      await strategy.setTokenContract(await baseAsset.getAddress(), await baseAsset.getAddress());

      // No commands needed - withdraw executes protocol operations itself
      const commands: Command[] = [];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      const actualWithdrawn = await strategy.connect(parent).withdraw.staticCall(
        ethers.parseEther("0.5"), // 50%
        await baseAsset.getAddress(),
        ethers.ZeroAddress, // flashLoanToken
        0, // providedAmount
        0, // expectedAmount
        data
      );

      // Execute actual withdrawal
      await strategy.connect(parent).withdraw(
        ethers.parseEther("0.5"),
        await baseAsset.getAddress(),
        ethers.ZeroAddress,
        0,
        0,
        data
      );

      // Should withdraw 50% of collateral
      const expectedRemaining = collateralAmount / 2n;
      expect(await strategy.collateral(await baseAsset.getAddress())).to.equal(expectedRemaining);
      expect(actualWithdrawn).to.equal(collateralAmount / 2n);
    });

    it("Should execute REPAY command", async function () {
      const debtAmount = 500n * 10n ** BigInt(BASE_ASSET_DECIMALS);
      const repayAmount = 300n * 10n ** BigInt(BASE_ASSET_DECIMALS);

      // Set up initial debt
      await strategy.setDebt(await baseAsset.getAddress(), debtAmount);

      const repayCommand = {
        cmdType: 3, // REPAY
        data: ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [await baseAsset.getAddress(), repayAmount]
        ),
      };

      const commands = [repayCommand];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      await strategy.connect(parent).rebalance( ethers.ZeroAddress, 0, 0, data);

      expect(await strategy.debt(await baseAsset.getAddress())).to.equal(
        debtAmount - repayAmount
      );
    });

    it("Should execute multiple commands in sequence", async function () {
      const supplyAmount = 1000n * 10n ** BigInt(BASE_ASSET_DECIMALS);
      const borrowAmount = 500n * 10n ** BigInt(BASE_ASSET_DECIMALS);

      const supplyCommand = {
        cmdType: SUPPLY,
        data: ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [await baseAsset.getAddress(), supplyAmount]
        ),
      };

      const borrowCommand = {
        cmdType: BORROW,
        data: ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [await baseAsset.getAddress(), borrowAmount]
        ),
      };

      const commands = [supplyCommand, borrowCommand];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      await baseAsset.transfer(await strategy.getAddress(), supplyAmount);

      await strategy.connect(parent).deposit(
        await baseAsset.getAddress(),
        supplyAmount,
        ethers.ZeroAddress, // flashLoanToken
        0, // providedAmount
        0, // expectedAmount
        data
      );

      expect(await strategy.collateral(await baseAsset.getAddress())).to.equal(supplyAmount);
      expect(await strategy.debt(await baseAsset.getAddress())).to.equal(borrowAmount);
    });
  });

  describe("Tracked Token Validation", function () {
    it("Should revert swap using untracked token during withdraw", async function () {
      const MockERC20Factory = await ethers.getContractFactory("MockERC20");
      const rewardToken = await MockERC20Factory.deploy(
        "Reward Token",
        "RWD",
        BASE_ASSET_DECIMALS,
        ethers.parseUnits("1000000", BASE_ASSET_DECIMALS)
      );

      // Transfer reward tokens directly to strategy (idle balance)
      const rewardAmount = ethers.parseUnits("100", BASE_ASSET_DECIMALS);
      await rewardToken.transfer(await strategy.getAddress(), rewardAmount);

      // Attempt to withdraw with a swap that touches the untracked reward token
      const swapData = ethers.AbiCoder.defaultAbiCoder().encode(
        [
          "uint8",
          "address",
          "uint256",
          "address",
          "uint256",
          "uint256",
          "bytes",
        ],
        [
          0, // SwapRouter.KyberSwap
          await rewardToken.getAddress(),
          rewardAmount,
          await baseAsset.getAddress(),
          0,
          50,
          "0x",
        ]
      );

      const commands = [
        {
          cmdType: SWAP,
          data: swapData,
        },
      ];

      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      await expect(
        strategy.connect(parent).withdraw(
          ethers.parseEther("0.5"),
          await baseAsset.getAddress(),
          ethers.ZeroAddress,
          0,
          0,
          data
        )
      ).to.be.revertedWithCustomError(strategy, "InvalidToken");
    });

    it("Should allow swaps with tracked tokens (success path)", async function () {
      // This test verifies that tracked tokens CAN be swapped during withdrawal
      // Unlike untracked tokens which should revert with InvalidToken

      const MockERC20Factory = await ethers.getContractFactory("MockERC20");
      const rewardToken = await MockERC20Factory.deploy(
        "Reward",
        "RWD",
        BASE_ASSET_DECIMALS,
        ethers.parseUnits("1000000", BASE_ASSET_DECIMALS)
      );

      // Add price feed for reward token
      const MockAggregatorFactory = await ethers.getContractFactory("MockAggregatorV3");
      const rewardFeed = await MockAggregatorFactory.deploy(ORACLE_DECIMALS);
      await rewardFeed.updateAnswer(2_00_000_000); // $2.00
      await priceOracle.addPriceFeed(await rewardToken.getAddress(), await rewardFeed.getAddress());

      // Track reward token
      await strategy.addTrackedToken(await rewardToken.getAddress());

      // Setup collateral and idle balances
      const collateralAmount = ethers.parseUnits("1000", BASE_ASSET_DECIMALS);
      const rewardIdleAmount = ethers.parseUnits("100", BASE_ASSET_DECIMALS);
      const baseIdleAmount = ethers.parseUnits("500", BASE_ASSET_DECIMALS);

      await strategy.setCollateral(await baseAsset.getAddress(), collateralAmount);
      await baseAsset.transfer(await strategy.getAddress(), baseIdleAmount);
      await rewardToken.transfer(await strategy.getAddress(), rewardIdleAmount);

      // Setup MockSwapRouter
      const MockSwapRouterFactory = await ethers.getContractFactory("MockSwapRouter");
      const mockRouter = await MockSwapRouterFactory.deploy();
      await strategy.setSwapRouter(0, await mockRouter.getAddress()); // SwapRouter.KyberSwap = 0

      // Configure router with minimal slippage
      await mockRouter.setSlippage(30); // 0.3%

      // Swap params: 10 reward tokens → ~20 baseAsset (because reward is $2, base is $1)
      // Router will apply 0.3% slippage, so actual output = 20 * (1 - 0.003) = 19.94
      const swapAmountIn = ethers.parseUnits("10", BASE_ASSET_DECIMALS);
      const idealOut = ethers.parseUnits("20", BASE_ASSET_DECIMALS);
      const minAmountOut = (idealOut * 99n) / 100n; // Accept up to 1% slippage

      // Fund router so it can return tokens
      await baseAsset.transfer(await mockRouter.getAddress(), idealOut);

      // Encode swap data for MockSwapRouter's fallback
      const routerCalldata = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "uint256", "address", "uint256"],
        [await rewardToken.getAddress(), swapAmountIn, await baseAsset.getAddress(), idealOut]
      );

      // Create SWAP command
      const swapData = ethers.AbiCoder.defaultAbiCoder().encode(
        [
          "uint8",
          "address",
          "uint256",
          "address",
          "uint256",
          "uint256",
          "bytes",
        ],
        [
          0, // SwapRouter.KyberSwap
          await rewardToken.getAddress(), // tracked token - should be allowed
          swapAmountIn,
          await baseAsset.getAddress(),
          minAmountOut, // Accept up to 1% slippage
          100, // maxOracleSlippageBps = 1%
          routerCalldata,
        ]
      );

      const commands = [{ cmdType: SWAP, data: swapData }];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      const rewardBalanceBefore = await rewardToken.balanceOf(await strategy.getAddress());

      // Should NOT revert - tracked tokens are allowed
      await strategy.connect(parent).withdraw(
        ethers.parseEther("0.5"), // 50% withdraw
        await baseAsset.getAddress(),
        ethers.ZeroAddress,
        0,
        0,
        data
      );

      // Verify swap executed: reward balance decreased
      const rewardBalanceAfter = await rewardToken.balanceOf(await strategy.getAddress());
      expect(rewardBalanceAfter).to.be.lt(rewardBalanceBefore);
      expect(rewardBalanceBefore - rewardBalanceAfter).to.equal(swapAmountIn);
    });
  });
  describe("Total Assets Calculation", function () {
    it("Should return collateral - debt", async function () {
      const collateralAmount = 1000n * 10n ** BigInt(BASE_ASSET_DECIMALS);
      const debtAmount = 300n * 10n ** BigInt(BASE_ASSET_DECIMALS);

      await strategy.setCollateral(await baseAsset.getAddress(), collateralAmount);
      await strategy.setDebt(await baseAsset.getAddress(), debtAmount);

      const totalAssets = await strategy.totalAssets();
      expect(totalAssets).to.equal(collateralAmount - debtAmount);
    });

    it("Should return 0 if debt exceeds collateral", async function () {
      const collateralAmount = 300n * 10n ** BigInt(BASE_ASSET_DECIMALS);
      const debtAmount = 1000n * 10n ** BigInt(BASE_ASSET_DECIMALS);

      await strategy.setCollateral(await baseAsset.getAddress(), collateralAmount);
      await strategy.setDebt(await baseAsset.getAddress(), debtAmount);

      const totalAssets = await strategy.totalAssets();
      expect(totalAssets).to.equal(0);
    });
  });

  describe("Events", function () {
    it("Should emit Deposited event", async function () {
      const depositAmount = 1000n * 10n ** BigInt(BASE_ASSET_DECIMALS);
      const commands: Command[] = [];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      await expect(
        strategy.connect(parent).deposit(
          await baseAsset.getAddress(),
          depositAmount,
          ethers.ZeroAddress, // flashLoanToken
          0, // providedAmount
          0, // expectedAmount
          data
        )
      )
        .to.emit(strategy, "Deposited")
        .withArgs(
          await baseAsset.getAddress(),
          depositAmount,
          ethers.ZeroAddress, // flashLoanToken
          0, // providedAmount
          0 // expectedAmount
        );
    });

    it("Should emit Withdrawn event", async function () {
      const percentage = ethers.parseEther("1");
      const commands: Command[] = [];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      await expect(
        strategy.connect(parent).withdraw(
          percentage,
          await baseAsset.getAddress(),
          ethers.ZeroAddress, // flashLoanToken
          0, // providedAmount
          0, // expectedAmount
          data
        )
      )
        .to.emit(strategy, "Withdrawn")
        .withArgs(
          percentage,
          await baseAsset.getAddress(),
          0, // actualWithdrawn
          ethers.ZeroAddress, // flashLoanToken
          0, // providedAmount
          0 // expectedAmount
        );
    });

    it("Should emit Rebalanced event", async function () {
      const commands: Command[] = [];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      await expect(
        strategy.connect(parent).rebalance( ethers.ZeroAddress, 0, 0, data)
      )
        .to.emit(strategy, "Rebalanced")
        .withArgs(ethers.ZeroAddress, 0, 0);
    });
  });

  describe("Security Validations", function () {
    it("Should revert withdraw with outputToken = address(0)", async function () {
      const commands: Command[] = [];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      await expect(
        strategy.connect(parent).withdraw(
          ethers.parseEther("0.5"),
          ethers.ZeroAddress, // invalid outputToken
          ethers.ZeroAddress,
          0,
          0,
          data
        )
      ).to.be.revertedWithCustomError(strategy, "InvalidToken");
    });

    it("Should revert deposit with untracked flashLoanToken", async function () {
      const MockERC20Factory = await ethers.getContractFactory("MockERC20");
      const untrackedToken = await MockERC20Factory.deploy(
        "Untracked",
        "UNT",
        BASE_ASSET_DECIMALS,
        ethers.parseUnits("1000000", BASE_ASSET_DECIMALS)
      );

      const commands: Command[] = [];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      await expect(
        strategy.connect(parent).deposit(
          await baseAsset.getAddress(),
          1000,
          await untrackedToken.getAddress(), // untracked flash loan token
          1000,
          1000,
          data
        )
      ).to.be.revertedWithCustomError(strategy, "InvalidToken");
    });

    it("Should revert withdraw with untracked flashLoanToken", async function () {
      const MockERC20Factory = await ethers.getContractFactory("MockERC20");
      const untrackedToken = await MockERC20Factory.deploy(
        "Untracked",
        "UNT",
        BASE_ASSET_DECIMALS,
        ethers.parseUnits("1000000", BASE_ASSET_DECIMALS)
      );

      await strategy.setCollateral(await baseAsset.getAddress(), 1000);

      const commands: Command[] = [];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      await expect(
        strategy.connect(parent).withdraw(
          ethers.parseEther("0.5"),
          await baseAsset.getAddress(),
          await untrackedToken.getAddress(), // untracked flash loan token
          1000,
          1000,
          data
        )
      ).to.be.revertedWithCustomError(strategy, "InvalidToken");
    });
  });

  describe("Proportional Withdrawal Validation", function () {
    it("Should maintain proportional balances for tracked tokens (50% withdraw)", async function () {
      const MockERC20Factory = await ethers.getContractFactory("MockERC20");

      // Create tracked reward token
      const rewardToken = await MockERC20Factory.deploy(
        "Reward",
        "RWD",
        BASE_ASSET_DECIMALS,
        ethers.parseUnits("1000000", BASE_ASSET_DECIMALS)
      );

      // Add price feed for reward token
      const MockAggregatorFactory = await ethers.getContractFactory("MockAggregatorV3");
      const rewardFeed = await MockAggregatorFactory.deploy(ORACLE_DECIMALS);
      await rewardFeed.updateAnswer(2_00_000_000); // $2.00
      await priceOracle.addPriceFeed(await rewardToken.getAddress(), await rewardFeed.getAddress());

      // Track reward token
      await strategy.addTrackedToken(await rewardToken.getAddress());

      // Setup initial balances
      const baseAssetAmount = ethers.parseUnits("1000", BASE_ASSET_DECIMALS);
      const rewardAmount = ethers.parseUnits("100", BASE_ASSET_DECIMALS);

      await baseAsset.transfer(await strategy.getAddress(), baseAssetAmount);
      await rewardToken.transfer(await strategy.getAddress(), rewardAmount);

      // Set collateral
      await strategy.setCollateral(await baseAsset.getAddress(), baseAssetAmount);

      const commands: Command[] = [];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      // Withdraw 50%
      await strategy.connect(parent).withdraw(
        ethers.parseEther("0.5"),
        await baseAsset.getAddress(),
        ethers.ZeroAddress,
        0,
        0,
        data
      );

      // Check that at least 50% remains for each tracked token
      const baseAssetBalance = await baseAsset.balanceOf(await strategy.getAddress());
      const rewardBalance = await rewardToken.balanceOf(await strategy.getAddress());

      // Should have at least 50% remaining (might have more due to collateral withdrawal)
      expect(rewardBalance).to.be.gte(rewardAmount / 2n);

      // BaseAsset should have withdrawn amount + remaining idle
      // Withdrawn from collateral: 500, remaining idle should be >= 500
      expect(baseAssetBalance).to.be.gte(baseAssetAmount / 2n);
    });

    it("Should maintain proportional balances for tracked tokens (25% withdraw)", async function () {
      const MockERC20Factory = await ethers.getContractFactory("MockERC20");
      const rewardToken = await MockERC20Factory.deploy(
        "Reward",
        "RWD",
        BASE_ASSET_DECIMALS,
        ethers.parseUnits("1000000", BASE_ASSET_DECIMALS)
      );

      const MockAggregatorFactory = await ethers.getContractFactory("MockAggregatorV3");
      const rewardFeed = await MockAggregatorFactory.deploy(ORACLE_DECIMALS);
      await rewardFeed.updateAnswer(2_00_000_000);
      await priceOracle.addPriceFeed(await rewardToken.getAddress(), await rewardFeed.getAddress());

      await strategy.addTrackedToken(await rewardToken.getAddress());

      const baseAssetAmount = ethers.parseUnits("1000", BASE_ASSET_DECIMALS);
      const rewardAmount = ethers.parseUnits("200", BASE_ASSET_DECIMALS);

      await baseAsset.transfer(await strategy.getAddress(), baseAssetAmount);
      await rewardToken.transfer(await strategy.getAddress(), rewardAmount);
      await strategy.setCollateral(await baseAsset.getAddress(), baseAssetAmount);

      const commands: Command[] = [];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      await strategy.connect(parent).withdraw(
        ethers.parseEther("0.25"), // 25%
        await baseAsset.getAddress(),
        ethers.ZeroAddress,
        0,
        0,
        data
      );

      const rewardBalance = await rewardToken.balanceOf(await strategy.getAddress());

      // Should have at least 75% remaining
      expect(rewardBalance).to.be.gte((rewardAmount * 75n) / 100n);
    });
  });

  describe("Total Assets Calculation - Complex Scenarios", function () {
    it("Should correctly calculate totalAssets with tracked token idle balances", async function () {
      const MockERC20Factory = await ethers.getContractFactory("MockERC20");
      const rewardToken = await MockERC20Factory.deploy(
        "Reward",
        "RWD",
        6, // different decimals
        ethers.parseUnits("1000000", 6)
      );

      // Add price feed
      const MockAggregatorFactory = await ethers.getContractFactory("MockAggregatorV3");
      const rewardFeed = await MockAggregatorFactory.deploy(ORACLE_DECIMALS);
      await rewardFeed.updateAnswer(3_00_000_000); // $3.00
      await priceOracle.addPriceFeed(await rewardToken.getAddress(), await rewardFeed.getAddress());

      // Track reward token
      await strategy.addTrackedToken(await rewardToken.getAddress());

      // Setup:
      // - Collateral: 1000 USDC ($1 each) = $1000
      // - Debt: 300 USDC = $300
      // - Idle base asset: 100 USDC = $100
      // - Idle reward: 50 RWD ($3 each) = $150
      // Total value: $1000 + $100 + $150 - $300 = $950
      // In base asset terms: $950 / $1 = 950 USDC

      const collateralAmount = ethers.parseUnits("1000", BASE_ASSET_DECIMALS);
      const debtAmount = ethers.parseUnits("300", BASE_ASSET_DECIMALS);
      const idleBase = ethers.parseUnits("100", BASE_ASSET_DECIMALS);
      const idleReward = ethers.parseUnits("50", 6);

      await strategy.setCollateral(await baseAsset.getAddress(), collateralAmount);
      await strategy.setDebt(await baseAsset.getAddress(), debtAmount);
      await baseAsset.transfer(await strategy.getAddress(), idleBase);
      await rewardToken.transfer(await strategy.getAddress(), idleReward);

      const totalAssets = await strategy.totalAssets();

      // Expected: (1000 + 100 + 150 - 300) = 950 USDC
      expect(totalAssets).to.equal(ethers.parseUnits("950", BASE_ASSET_DECIMALS));
    });

    it("Should correctly calculate totalAssets with different collateral and debt assets", async function () {
      // Setup:
      // - Collateral: 2000 USDC = $2000
      // - Debt: 500 USDC = $500
      // - Idle: 0
      // Total: $2000 - $500 = $1500 = 1500 USDC

      const collateralAmount = ethers.parseUnits("2000", BASE_ASSET_DECIMALS);
      const debtAmount = ethers.parseUnits("500", BASE_ASSET_DECIMALS);

      await strategy.setCollateral(await baseAsset.getAddress(), collateralAmount);
      await strategy.setDebt(await baseAsset.getAddress(), debtAmount);

      const totalAssets = await strategy.totalAssets();
      expect(totalAssets).to.equal(ethers.parseUnits("1500", BASE_ASSET_DECIMALS));
    });

    it("Should return 0 when total debt exceeds total value", async function () {
      // Setup:
      // - Collateral: 500 USDC = $500
      // - Debt: 600 USDC = $600
      // - Idle reward: 50 units ($3 each) = $150
      // Total: $500 + $150 - $600 = $50 (but already tested, let's make it negative)
      // Total: $500 - $800 = -$300 → should return 0

      const collateralAmount = ethers.parseUnits("500", BASE_ASSET_DECIMALS);
      const debtAmount = ethers.parseUnits("800", BASE_ASSET_DECIMALS);

      await strategy.setCollateral(await baseAsset.getAddress(), collateralAmount);
      await strategy.setDebt(await baseAsset.getAddress(), debtAmount);

      const totalAssets = await strategy.totalAssets();
      expect(totalAssets).to.equal(0);
    });
  });

  describe("Edge Cases", function () {
    it("Should revert withdraw with invalid percentage (0)", async function () {
      const commands: Command[] = [];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      await expect(
        strategy.connect(parent).withdraw(
          0,
          await baseAsset.getAddress(), ethers.ZeroAddress, 0, 0,
          data
        )
      ).to.be.revertedWithCustomError(strategy, "InvalidPercentage");
    });

    it("Should revert withdraw with invalid percentage (>100%)", async function () {
      const commands: Command[] = [];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      await expect(
        strategy.connect(parent).withdraw(
          ethers.parseEther("1.01"), // 101%
          await baseAsset.getAddress(),
          ethers.ZeroAddress, 0, 0, data
        )
      ).to.be.revertedWithCustomError(strategy, "InvalidPercentage");
    });

    it("Should handle 100% withdrawal", async function () {
      const collateralAmount = 1000n * 10n ** BigInt(BASE_ASSET_DECIMALS);
      await strategy.setCollateral(await baseAsset.getAddress(), collateralAmount);

      // Register token contract to enable minting on withdraw
      await strategy.setTokenContract(await baseAsset.getAddress(), await baseAsset.getAddress());

      // No commands needed - withdraw executes protocol operations itself
      const commands: Command[] = [];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      const actualWithdrawn = await strategy.connect(parent).withdraw.staticCall(
        ethers.parseEther("1"), // 100%
        await baseAsset.getAddress(),
        ethers.ZeroAddress, // flashLoanToken
        0, // providedAmount
        0, // expectedAmount
        data
      );

      await strategy.connect(parent).withdraw(
        ethers.parseEther("1"),
        await baseAsset.getAddress(),
        ethers.ZeroAddress,
        0,
        0,
        data
      );

      expect(await strategy.collateral(await baseAsset.getAddress())).to.equal(0);
      expect(actualWithdrawn).to.equal(collateralAmount);
    });
  });

  describe("actualWithdrawn Return Value", function () {
    it("Should return correct actualWithdrawn for simple protocol withdrawal", async function () {
      const collateralAmount = ethers.parseUnits("1000", BASE_ASSET_DECIMALS);
      await strategy.setCollateral(await baseAsset.getAddress(), collateralAmount);

      // Register token contract to enable minting on withdraw
      await strategy.setTokenContract(await baseAsset.getAddress(), await baseAsset.getAddress());

      const commands: Command[] = [];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      // Withdraw 50%
      const actualWithdrawn = await strategy.connect(parent).withdraw.staticCall(
        ethers.parseEther("0.5"), // 50%
        await baseAsset.getAddress(),
        ethers.ZeroAddress,
        0,
        0,
        data
      );

      // Should return 500 USDC (50% of 1000)
      expect(actualWithdrawn).to.equal(collateralAmount / 2n);
    });

    it("Should return correct actualWithdrawn when outputToken == flashLoanToken", async function () {
      const collateralAmount = ethers.parseUnits("1000", BASE_ASSET_DECIMALS);
      const flashLoanAmount = ethers.parseUnits("200", BASE_ASSET_DECIMALS);

      await strategy.setCollateral(await baseAsset.getAddress(), collateralAmount);

      // Register token contract to enable minting on withdraw
      await strategy.setTokenContract(await baseAsset.getAddress(), await baseAsset.getAddress());

      // Parent provides flash loan
      await baseAsset.transfer(await strategy.getAddress(), flashLoanAmount);

      const commands: Command[] = [];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      // Withdraw 50% with flash loan
      const actualWithdrawn = await strategy.connect(parent).withdraw.staticCall(
        ethers.parseEther("0.5"), // 50%
        await baseAsset.getAddress(),
        await baseAsset.getAddress(), // flashLoanToken = outputToken
        flashLoanAmount, // providedAmount
        flashLoanAmount, // expectedAmount (must return flash loan)
        data
      );

      // Should return 500 USDC (50% of 1000), NOT including flash loan
      expect(actualWithdrawn).to.equal(collateralAmount / 2n);
    });

    it("Should return correct actualWithdrawn for 100% withdrawal", async function () {
      const collateralAmount = ethers.parseUnits("1000", BASE_ASSET_DECIMALS);
      await strategy.setCollateral(await baseAsset.getAddress(), collateralAmount);

      // Register token contract to enable minting on withdraw
      await strategy.setTokenContract(await baseAsset.getAddress(), await baseAsset.getAddress());

      const commands: Command[] = [];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      const actualWithdrawn = await strategy.connect(parent).withdraw.staticCall(
        ethers.parseEther("1"), // 100%
        await baseAsset.getAddress(),
        ethers.ZeroAddress,
        0,
        0,
        data
      );

      expect(actualWithdrawn).to.equal(collateralAmount);
    });

    it("Should return correct actualWithdrawn when expectedAmount > 0 but providedAmount = 0", async function () {
      const collateralAmount = ethers.parseUnits("1000", BASE_ASSET_DECIMALS);
      const idleAmount = ethers.parseUnits("300", BASE_ASSET_DECIMALS);
      const expectedAmount = ethers.parseUnits("100", BASE_ASSET_DECIMALS);

      await strategy.setCollateral(await baseAsset.getAddress(), collateralAmount);

      // Register token contract to enable minting on withdraw
      await strategy.setTokenContract(await baseAsset.getAddress(), await baseAsset.getAddress());

      // Strategy already has idle tokens
      await baseAsset.transfer(await strategy.getAddress(), idleAmount);

      const commands: Command[] = [];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      // Withdraw 50%, parent expects 100 tokens back from idle
      const actualWithdrawn = await strategy.connect(parent).withdraw.staticCall(
        ethers.parseEther("0.5"),
        await baseAsset.getAddress(),
        await baseAsset.getAddress(),
        0, // providedAmount = 0 (no flash loan provided)
        expectedAmount, // expectedAmount > 0 (take from idle)
        data
      );

      // actualWithdrawn = (idle + withdrawn) - idle_before - expectedAmount
      // = (300 + 500) - 300 - 100 = 400
      // This is correct because parent gets 100 from idle + 400 net new = 500 total
      expect(actualWithdrawn).to.equal(collateralAmount / 2n - expectedAmount);
    });

    it("Should return zero actualWithdrawn when no collateral to withdraw", async function () {
      // No collateral set
      await strategy.setCollateral(await baseAsset.getAddress(), 0);

      const commands: Command[] = [];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      const actualWithdrawn = await strategy.connect(parent).withdraw.staticCall(
        ethers.parseEther("0.5"),
        await baseAsset.getAddress(),
        ethers.ZeroAddress,
        0,
        0,
        data
      );

      expect(actualWithdrawn).to.equal(0);
    });
  });

  describe("Price Oracle Management", function () {
    it("Should allow parent to update price oracle", async function () {
      // Deploy new price oracle
      const PriceOracleFactory = await ethers.getContractFactory("PriceOracle");
      const newOracle = await PriceOracleFactory.deploy(await pendleOracle.getAddress());

      const oldOracle = await strategy.priceOracle();

      // Update oracle
      await expect(strategy.connect(parent).setOracle(await newOracle.getAddress()))
        .to.emit(strategy, "OracleUpdated")
        .withArgs(oldOracle, await newOracle.getAddress());

      // Verify update
      expect(await strategy.priceOracle()).to.equal(await newOracle.getAddress());
    });

    it("Should not allow non-parent to update price oracle", async function () {
      const PriceOracleFactory = await ethers.getContractFactory("PriceOracle");
      const newOracle = await PriceOracleFactory.deploy(await pendleOracle.getAddress());

      await expect(
        strategy.connect(user).setOracle(await newOracle.getAddress())
      ).to.be.revertedWithCustomError(strategy, "Unauthorized");
    });

    it("Should revert if new oracle is zero address", async function () {
      await expect(
        strategy.connect(parent).setOracle(ethers.ZeroAddress)
      ).to.be.revertedWithCustomError(strategy, "ZeroAddress");
    });
  });
});
