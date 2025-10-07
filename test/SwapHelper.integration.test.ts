import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import {
  MockERC20,
  PriceOracle,
  MockPendleOracle,
  MockAggregatorV3,
  MockSwapHelper,
  MockSwapRouter
} from "../typechain-types";

describe("SwapHelper Integration Tests", function () {
  let owner: SignerWithAddress;
  let user: SignerWithAddress;
  let priceOracle: PriceOracle;
  let pendleOracle: MockPendleOracle;
  let usdcFeed: MockAggregatorV3;
  let usdtFeed: MockAggregatorV3;
  let usdc: MockERC20;
  let usdt: MockERC20;
  let swapHelper: MockSwapHelper;
  let mockRouter: MockSwapRouter;

  const USDC_DECIMALS = 6;
  const USDT_DECIMALS = 6;
  const ORACLE_DECIMALS = 8;
  const MAX_ORACLE_SLIPPAGE_BPS = 50n; // 0.5%

  beforeEach(async function () {
    [owner, user] = await ethers.getSigners();

    // Deploy mock tokens
    const MockERC20Factory = await ethers.getContractFactory("MockERC20");
    const initialSupply = ethers.parseUnits("1000000", USDC_DECIMALS);
    usdc = await MockERC20Factory.deploy("USD Coin", "USDC", USDC_DECIMALS, initialSupply);
    usdt = await MockERC20Factory.deploy("Tether USD", "USDT", USDT_DECIMALS, initialSupply);

    // Deploy mock price feeds
    const MockAggregatorFactory = await ethers.getContractFactory("MockAggregatorV3");
    usdcFeed = await MockAggregatorFactory.deploy(ORACLE_DECIMALS);
    await usdcFeed.updateAnswer(1_00_000_000); // $1.00
    usdtFeed = await MockAggregatorFactory.deploy(ORACLE_DECIMALS);
    await usdtFeed.updateAnswer(1_00_000_000); // $1.00

    // Deploy Pendle Oracle mock
    const MockPendleOracleFactory = await ethers.getContractFactory("MockPendleOracle");
    pendleOracle = await MockPendleOracleFactory.deploy();

    // Deploy PriceOracle
    const PriceOracleFactory = await ethers.getContractFactory("PriceOracle");
    priceOracle = await PriceOracleFactory.deploy(await pendleOracle.getAddress());

    // Register price feeds
    await priceOracle.addPriceFeed(await usdc.getAddress(), await usdcFeed.getAddress());
    await priceOracle.addPriceFeed(await usdt.getAddress(), await usdtFeed.getAddress());

    // Deploy MockSwapHelper
    const MockSwapHelperFactory = await ethers.getContractFactory("MockSwapHelper");
    swapHelper = await MockSwapHelperFactory.deploy(await priceOracle.getAddress());

    // Deploy MockSwapRouter
    const MockSwapRouterFactory = await ethers.getContractFactory("MockSwapRouter");
    mockRouter = await MockSwapRouterFactory.deploy();

    // Configure SwapHelper with router
    await swapHelper.setSwapRouter(0, await mockRouter.getAddress()); // 0 = KyberSwap

    // Fund mockRouter with USDT for swaps
    await usdt.mint(await mockRouter.getAddress(), ethers.parseUnits("1000000", USDT_DECIMALS));
  });

  describe("Successful Swaps", function () {
    it("Should execute swap with exact exchange rate (no slippage)", async function () {
      const amountIn = 1000n * 10n ** BigInt(USDC_DECIMALS); // 1000 USDC
      const expectedOut = 1000n * 10n ** BigInt(USDT_DECIMALS); // 1000 USDT

      // Fund swapHelper with USDC
      await usdc.mint(await swapHelper.getAddress(), amountIn);

      // Prepare swap data
      const swapData = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "uint256", "address", "uint256"],
        [await usdc.getAddress(), amountIn, await usdt.getAddress(), expectedOut]
      );

      // Execute swap
      const tx = await swapHelper.swap(
        0, // KyberSwap
        await usdc.getAddress(),
        amountIn,
        await usdt.getAddress(),
        expectedOut, // minAmountOut
        MAX_ORACLE_SLIPPAGE_BPS,
        swapData
      );

      // Check event
      await expect(tx)
        .to.emit(swapHelper, "SwapExecuted")
        .withArgs(
          0,
          await usdc.getAddress(),
          amountIn,
          await usdt.getAddress(),
          expectedOut,
          expectedOut,
          1000_00_000_000n, // usdValueIn ($1000)
          1000_00_000_000n  // usdValueOut ($1000)
        );

      // Check balances
      expect(await usdt.balanceOf(await swapHelper.getAddress())).to.equal(expectedOut);
      expect(await usdc.balanceOf(await swapHelper.getAddress())).to.equal(0);
    });

    it("Should execute swap with acceptable slippage (0.3%)", async function () {
      const amountIn = 1000n * 10n ** BigInt(USDC_DECIMALS);
      const expectedOut = 1000n * 10n ** BigInt(USDT_DECIMALS);

      // Set router slippage to 30 bps (0.3%)
      await mockRouter.setSlippage(30);

      await usdc.mint(await swapHelper.getAddress(), amountIn);

      const swapData = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "uint256", "address", "uint256"],
        [await usdc.getAddress(), amountIn, await usdt.getAddress(), expectedOut]
      );

      const actualOut = 997n * 10n ** BigInt(USDT_DECIMALS); // 0.3% slippage

      await swapHelper.swap(
        0,
        await usdc.getAddress(),
        amountIn,
        await usdt.getAddress(),
        actualOut, // minAmountOut
        MAX_ORACLE_SLIPPAGE_BPS, // 0.5% max
        swapData
      );

      // Should succeed with 0.3% slippage (within 0.5% limit)
      expect(await usdt.balanceOf(await swapHelper.getAddress())).to.equal(actualOut);
    });

    it("Should clean up approvals after successful swap", async function () {
      const amountIn = 1000n * 10n ** BigInt(USDC_DECIMALS);
      const expectedOut = 1000n * 10n ** BigInt(USDT_DECIMALS);

      await usdc.mint(await swapHelper.getAddress(), amountIn);

      const swapData = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "uint256", "address", "uint256"],
        [await usdc.getAddress(), amountIn, await usdt.getAddress(), expectedOut]
      );

      await swapHelper.swap(
        0,
        await usdc.getAddress(),
        amountIn,
        await usdt.getAddress(),
        expectedOut,
        MAX_ORACLE_SLIPPAGE_BPS,
        swapData
      );

      // Check that allowance was reset to 0
      const allowance = await usdc.allowance(
        await swapHelper.getAddress(),
        await mockRouter.getAddress()
      );
      expect(allowance).to.equal(0);
    });
  });

  describe("Slippage Protection", function () {
    it("Should revert if actual output is below minAmountOut", async function () {
      const amountIn = 1000n * 10n ** BigInt(USDC_DECIMALS);
      const expectedOut = 1000n * 10n ** BigInt(USDT_DECIMALS);

      // Set high slippage
      await mockRouter.setSlippage(100); // 1%

      await usdc.mint(await swapHelper.getAddress(), amountIn);

      const swapData = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "uint256", "address", "uint256"],
        [await usdc.getAddress(), amountIn, await usdt.getAddress(), expectedOut]
      );

      // minAmountOut = 995 (0.5% slippage), but actual will be 990 (1% slippage)
      await expect(
        swapHelper.swap(
          0,
          await usdc.getAddress(),
          amountIn,
          await usdt.getAddress(),
          995n * 10n ** BigInt(USDT_DECIMALS), // minAmountOut
          MAX_ORACLE_SLIPPAGE_BPS,
          swapData
        )
      ).to.be.revertedWithCustomError(swapHelper, "SlippageTooHigh");
    });

    it("Should revert if oracle slippage exceeds maxOracleSlippageBps", async function () {
      const amountIn = 1000n * 10n ** BigInt(USDC_DECIMALS);
      const expectedOut = 1000n * 10n ** BigInt(USDT_DECIMALS);

      // Set router slippage to 60 bps (0.6%) - exceeds 50 bps max
      await mockRouter.setSlippage(60);

      await usdc.mint(await swapHelper.getAddress(), amountIn);

      const swapData = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "uint256", "address", "uint256"],
        [await usdc.getAddress(), amountIn, await usdt.getAddress(), expectedOut]
      );

      const actualOut = 994n * 10n ** BigInt(USDT_DECIMALS); // 0.6% slippage

      await expect(
        swapHelper.swap(
          0,
          await usdc.getAddress(),
          amountIn,
          await usdt.getAddress(),
          actualOut, // minAmountOut OK
          MAX_ORACLE_SLIPPAGE_BPS, // But oracle check will fail
          swapData
        )
      ).to.be.revertedWithCustomError(swapHelper, "OracleSlippageCheckFailed");
    });

    it("Should allow configurable oracle slippage tolerance", async function () {
      const amountIn = 1000n * 10n ** BigInt(USDC_DECIMALS);
      const expectedOut = 1000n * 10n ** BigInt(USDT_DECIMALS);

      // Set router slippage to 100 bps (1%)
      await mockRouter.setSlippage(100);

      await usdc.mint(await swapHelper.getAddress(), amountIn);

      const swapData = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "uint256", "address", "uint256"],
        [await usdc.getAddress(), amountIn, await usdt.getAddress(), expectedOut]
      );

      const actualOut = 990n * 10n ** BigInt(USDT_DECIMALS); // 1% slippage

      // Should succeed with 1% tolerance (100 bps)
      await swapHelper.swap(
        0,
        await usdc.getAddress(),
        amountIn,
        await usdt.getAddress(),
        actualOut,
        100n, // maxOracleSlippageBps = 1%
        swapData
      );

      expect(await usdt.balanceOf(await swapHelper.getAddress())).to.equal(actualOut);
    });
  });

  describe("Reentrancy Protection", function () {
    it("Should prevent reentrancy attacks", async function () {
      const amountIn = 1000n * 10n ** BigInt(USDC_DECIMALS);
      const expectedOut = 1000n * 10n ** BigInt(USDT_DECIMALS);

      await usdc.mint(await swapHelper.getAddress(), amountIn);

      // Prepare reentrancy attack calldata
      const reentrancySwapData = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "uint256", "address", "uint256"],
        [await usdc.getAddress(), amountIn, await usdt.getAddress(), expectedOut]
      );

      const reentrancyCalldata = swapHelper.interface.encodeFunctionData("swap", [
        0,
        await usdc.getAddress(),
        amountIn,
        await usdt.getAddress(),
        expectedOut,
        MAX_ORACLE_SLIPPAGE_BPS,
        reentrancySwapData
      ]);

      // Configure router to attempt reentrancy
      await mockRouter.setReentrancy(await swapHelper.getAddress(), reentrancyCalldata);

      const swapData = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "uint256", "address", "uint256"],
        [await usdc.getAddress(), amountIn, await usdt.getAddress(), expectedOut]
      );

      // Swap should revert - either due to reentrancy guard or swap failure
      // The reentrancy attempt will be blocked by the guard
      await expect(
        swapHelper.swap(
          0,
          await usdc.getAddress(),
          amountIn,
          await usdt.getAddress(),
          expectedOut,
          MAX_ORACLE_SLIPPAGE_BPS,
          swapData
        )
      ).to.be.reverted; // Reentrancy causes failure (either SwapFailed or ReentrancyGuardReentrantCall)
    });
  });

  describe("Input Validation", function () {
    it("Should revert for zero token addresses", async function () {
      const swapData = "0x";

      await expect(
        swapHelper.swap(
          0,
          ethers.ZeroAddress,
          1000,
          await usdt.getAddress(),
          1000,
          MAX_ORACLE_SLIPPAGE_BPS,
          swapData
        )
      ).to.be.revertedWithCustomError(swapHelper, "InvalidToken");
    });

    it("Should revert for zero amounts", async function () {
      const swapData = "0x";

      await expect(
        swapHelper.swap(
          0,
          await usdc.getAddress(),
          0,
          await usdt.getAddress(),
          1000,
          MAX_ORACLE_SLIPPAGE_BPS,
          swapData
        )
      ).to.be.revertedWithCustomError(swapHelper, "InvalidAmount");
    });

    it("Should revert for invalid maxOracleSlippageBps (> 10000)", async function () {
      const swapData = "0x";

      await expect(
        swapHelper.swap(
          0,
          await usdc.getAddress(),
          1000,
          await usdt.getAddress(),
          1000,
          10001n, // > 100%
          swapData
        )
      ).to.be.revertedWithCustomError(swapHelper, "InvalidAmount");
    });

    it("Should revert for unconfigured router", async function () {
      const swapData = "0x";

      await expect(
        swapHelper.swap(
          1, // Odos router - not configured
          await usdc.getAddress(),
          1000,
          await usdt.getAddress(),
          1000,
          MAX_ORACLE_SLIPPAGE_BPS,
          swapData
        )
      ).to.be.revertedWithCustomError(swapHelper, "InvalidRouter");
    });
  });

  describe("Approval Management", function () {
    it("Should use precise approvals (not max)", async function () {
      const amountIn = 1000n * 10n ** BigInt(USDC_DECIMALS);
      const expectedOut = 1000n * 10n ** BigInt(USDT_DECIMALS);

      await usdc.mint(await swapHelper.getAddress(), amountIn);

      const swapData = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "uint256", "address", "uint256"],
        [await usdc.getAddress(), amountIn, await usdt.getAddress(), expectedOut]
      );

      // Check allowance before swap (should be 0)
      const allowanceBefore = await usdc.allowance(
        await swapHelper.getAddress(),
        await mockRouter.getAddress()
      );
      expect(allowanceBefore).to.equal(0);

      await swapHelper.swap(
        0,
        await usdc.getAddress(),
        amountIn,
        await usdt.getAddress(),
        expectedOut,
        MAX_ORACLE_SLIPPAGE_BPS,
        swapData
      );

      // Allowance should be reset to 0 after swap
      const allowanceAfter = await usdc.allowance(
        await swapHelper.getAddress(),
        await mockRouter.getAddress()
      );
      expect(allowanceAfter).to.equal(0);

      // Verify that approval was NOT type(uint256).max
      // (We can't directly check this, but the fact that it's 0 after confirms cleanup)
    });
  });

  describe("Event Logging", function () {
    it("Should emit SwapExecuted with all parameters including USD values", async function () {
      const amountIn = 1000n * 10n ** BigInt(USDC_DECIMALS);
      const expectedOut = 1000n * 10n ** BigInt(USDT_DECIMALS);

      await usdc.mint(await swapHelper.getAddress(), amountIn);

      const swapData = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "uint256", "address", "uint256"],
        [await usdc.getAddress(), amountIn, await usdt.getAddress(), expectedOut]
      );

      await expect(
        swapHelper.swap(
          0,
          await usdc.getAddress(),
          amountIn,
          await usdt.getAddress(),
          expectedOut,
          MAX_ORACLE_SLIPPAGE_BPS,
          swapData
        )
      )
        .to.emit(swapHelper, "SwapExecuted")
        .withArgs(
          0, // router
          await usdc.getAddress(), // tokenIn
          amountIn, // amountIn
          await usdt.getAddress(), // tokenOut
          expectedOut, // amountOut
          expectedOut, // minAmountOut
          1000_00_000_000n, // usdValueIn
          1000_00_000_000n  // usdValueOut
        );
    });

    it("Should log different USD values when token prices differ", async function () {
      // Update USDT price to $0.99
      await usdtFeed.updateAnswer(99_000_000); // $0.99 with 8 decimals

      const amountIn = 1000n * 10n ** BigInt(USDC_DECIMALS); // 1000 USDC = $1000
      const expectedOut = 1010n * 10n ** BigInt(USDT_DECIMALS); // 1010 USDT

      await usdc.mint(await swapHelper.getAddress(), amountIn);

      const swapData = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "uint256", "address", "uint256"],
        [await usdc.getAddress(), amountIn, await usdt.getAddress(), expectedOut]
      );

      // Calculate expected USD values
      const expectedUsdValueIn = 1000_00_000_000n; // 1000 USDC @ $1.00 = $1000
      const expectedUsdValueOut = 999_90_000_000n; // 1010 USDT @ $0.99 = $999.90

      await expect(
        swapHelper.swap(
          0,
          await usdc.getAddress(),
          amountIn,
          await usdt.getAddress(),
          expectedOut,
          MAX_ORACLE_SLIPPAGE_BPS,
          swapData
        )
      )
        .to.emit(swapHelper, "SwapExecuted")
        .withArgs(
          0, // router
          await usdc.getAddress(), // tokenIn
          amountIn, // amountIn
          await usdt.getAddress(), // tokenOut
          expectedOut, // amountOut
          expectedOut, // minAmountOut
          expectedUsdValueIn, // usdValueIn = $1000
          expectedUsdValueOut // usdValueOut = $999.90
        );
    });
  });
});
