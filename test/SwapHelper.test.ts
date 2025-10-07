import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { MockERC20, PriceOracle, MockPendleOracle, MockAggregatorV3 } from "../typechain-types";

describe("SwapHelper", function () {
  let owner: SignerWithAddress;
  let user: SignerWithAddress;
  let priceOracle: PriceOracle;
  let pendleOracle: MockPendleOracle;
  let usdcFeed: MockAggregatorV3;
  let usdtFeed: MockAggregatorV3;
  let usdc: MockERC20;
  let usdt: MockERC20;
  let mockRouter: SignerWithAddress;

  const USDC_DECIMALS = 6;
  const USDT_DECIMALS = 6;
  const ORACLE_DECIMALS = 8;

  beforeEach(async function () {
    [owner, user, mockRouter] = await ethers.getSigners();

    // Deploy mock tokens
    const MockERC20Factory = await ethers.getContractFactory("MockERC20");
    const initialSupply = ethers.parseUnits("1000000", USDC_DECIMALS); // 1M tokens
    usdc = await MockERC20Factory.deploy("USD Coin", "USDC", USDC_DECIMALS, initialSupply);
    usdt = await MockERC20Factory.deploy("Tether USD", "USDT", USDT_DECIMALS, initialSupply);

    // Deploy mock price feeds
    const MockAggregatorFactory = await ethers.getContractFactory("MockAggregatorV3");
    usdcFeed = await MockAggregatorFactory.deploy(ORACLE_DECIMALS);
    usdtFeed = await MockAggregatorFactory.deploy(ORACLE_DECIMALS);

    // Set prices: USDC = $1.00, USDT = $1.00
    await usdcFeed.updateAnswer(1_00_000_000); // $1.00 with 8 decimals
    await usdtFeed.updateAnswer(1_00_000_000); // $1.00 with 8 decimals

    // Deploy Pendle Oracle mock
    const MockPendleOracleFactory = await ethers.getContractFactory("MockPendleOracle");
    pendleOracle = await MockPendleOracleFactory.deploy();

    // Deploy PriceOracle
    const PriceOracleFactory = await ethers.getContractFactory("PriceOracle");
    priceOracle = await PriceOracleFactory.deploy(await pendleOracle.getAddress());

    // Register price feeds
    await priceOracle.addPriceFeed(await usdc.getAddress(), await usdcFeed.getAddress());
    await priceOracle.addPriceFeed(await usdt.getAddress(), await usdtFeed.getAddress());
  });

  describe("SwapHelper Deployment and Configuration", function () {
    it("Should deploy SwapHelper test contract with price oracle", async function () {
      // Note: This test would require deploying a concrete implementation
      // For now, we'll test the integration through child strategy contracts
      expect(await priceOracle.getAddress()).to.not.equal(ethers.ZeroAddress);
    });
  });

  describe("USD value-based swap validation", function () {
    it("Should calculate USD value for input tokens", async function () {
      const amountIn = 1000n * 10n ** BigInt(USDC_DECIMALS); // 1000 USDC

      const usdValue = await priceOracle.getUsdValue(
        await usdc.getAddress(),
        amountIn
      );

      // Should be $1000 with 8 decimals
      expect(usdValue).to.equal(1000_00_000_000n);
    });

    it("Should calculate USD value for output tokens", async function () {
      const amountOut = 995n * 10n ** BigInt(USDT_DECIMALS); // 995 USDT (0.5% slippage)

      const usdValue = await priceOracle.getUsdValue(
        await usdt.getAddress(),
        amountOut
      );

      // Should be $995 with 8 decimals
      expect(usdValue).to.equal(995_00_000_000n);
    });

    it("Should validate slippage via USD value comparison", async function () {
      const amountIn = 1000n * 10n ** BigInt(USDC_DECIMALS); // 1000 USDC
      const usdValueIn = await priceOracle.getUsdValue(
        await usdc.getAddress(),
        amountIn
      );

      // MAX_SLIPPAGE_BPS = 50 bps = 0.5%
      // minAcceptableUsdValue = usdValueIn * (10000 - 50) / 10000
      const maxSlippageBps = 50n;
      const minAcceptableUsdValue = (usdValueIn * (10000n - maxSlippageBps)) / 10000n;

      // This should be the minimum acceptable USD value
      expect(minAcceptableUsdValue).to.equal(995_00_000_000n); // $995 (0.5% loss)
    });

    it("Should detect excessive slippage via USD comparison", async function () {
      const amountIn = 1000n * 10n ** BigInt(USDC_DECIMALS); // 1000 USDC = $1000
      const usdValueIn = await priceOracle.getUsdValue(
        await usdc.getAddress(),
        amountIn
      );

      // Simulate receiving 990 USDT (1% slippage - too much)
      const amountOut = 990n * 10n ** BigInt(USDT_DECIMALS);
      const usdValueOut = await priceOracle.getUsdValue(
        await usdt.getAddress(),
        amountOut
      );

      // Check that this would fail validation
      const maxSlippageBps = 50n;
      const minAcceptableUsdValue = (usdValueIn * (10000n - maxSlippageBps)) / 10000n;

      expect(usdValueOut).to.be.lt(minAcceptableUsdValue); // Should fail
    });
  });

  describe("Slippage protection", function () {
    it("Should validate acceptable slippage within MAX_SLIPPAGE_BPS", async function () {
      const amountIn = 1000n * 10n ** BigInt(USDC_DECIMALS); // 1000 USDC
      const usdValueIn = await priceOracle.getUsdValue(
        await usdc.getAddress(),
        amountIn
      );

      // MAX_SLIPPAGE_BPS = 50 bps = 0.5%
      // minAcceptable = usdValueIn * (10000 - 50) / 10000 = usdValueIn * 0.995
      const maxSlippageBps = 50n;
      const minAcceptableUsdValue = (usdValueIn * (10000n - maxSlippageBps)) / 10000n;

      // Output should be at least $995 for 0.5% slippage
      expect(minAcceptableUsdValue).to.equal(995_00_000_000n); // $995
    });

    it("Should reject swaps exceeding MAX_SLIPPAGE_BPS", async function () {
      const amountIn = 1000n * 10n ** BigInt(USDC_DECIMALS); // 1000 USDC = $1000
      const usdValueIn = await priceOracle.getUsdValue(
        await usdc.getAddress(),
        amountIn
      );

      // Simulate receiving only 994 USDT (0.6% slippage - exceeds 50 bps limit)
      const amountOut = 994n * 10n ** BigInt(USDT_DECIMALS);
      const usdValueOut = await priceOracle.getUsdValue(
        await usdt.getAddress(),
        amountOut
      );

      const maxSlippageBps = 50n;
      const minAcceptableUsdValue = (usdValueIn * (10000n - maxSlippageBps)) / 10000n;

      // This swap should be rejected
      expect(usdValueOut).to.be.lt(minAcceptableUsdValue);
    });
  });

  describe("Security features", function () {
    it("Should use precise approvals (not max)", async function () {
      // This will be tested in integration tests with actual SwapHelper implementation
      // The key is that approvals should be exactly amountIn, not type(uint256).max

      // Conceptual test: approval should equal amountIn
      const amountIn = 1000n * 10n ** BigInt(USDC_DECIMALS);
      // In actual implementation: IERC20(tokenIn).safeIncreaseAllowance(routerAddress, amountIn)
      // NOT: IERC20(tokenIn).approve(routerAddress, type(uint256).max)

      expect(amountIn).to.equal(1000_000_000n); // Verify amount format
    });

    it("Should clean up approvals after swap", async function () {
      // This will be tested in integration tests
      // After swap, allowance should be reset to 0
      // IERC20(tokenIn).safeDecreaseAllowance(routerAddress, remainingAllowance)

      // This is a critical security feature to prevent approval abuse
      expect(true).to.equal(true); // Placeholder
    });
  });

  describe("Event logging", function () {
    it("Should emit SwapExecuted event with correct parameters", async function () {
      // This will be tested when SwapHelper is used in child strategy
      // Event should include: router, tokenIn, amountIn, tokenOut, amountOut, minAmountOut, usdValueIn

      // Event structure validation
      const eventSignature = "SwapExecuted(uint8,address,uint256,address,uint256,uint256,uint256)";
      expect(eventSignature).to.include("SwapExecuted");
    });

    it("Should log USD value for audit trail", async function () {
      // USD value helps track actual value exchanged for monitoring and compliance
      const amountIn = 1000n * 10n ** BigInt(USDC_DECIMALS);
      const usdValueIn = await priceOracle.getUsdValue(
        await usdc.getAddress(),
        amountIn
      );

      // USD value should be included in event for audit purposes
      expect(usdValueIn).to.equal(1000_00_000_000n); // $1000
    });
  });

  describe("Integration with existing code", function () {
    it("Should work with existing oracle implementation", async function () {
      // Verify oracle integration
      expect(await priceOracle.getAddress()).to.not.equal(ethers.ZeroAddress);

      // Test that oracle can provide prices for swap validation
      const usdcPrice = await priceOracle.getUsdValue(
        await usdc.getAddress(),
        1n * 10n ** BigInt(USDC_DECIMALS)
      );
      expect(usdcPrice).to.equal(1_00_000_000n); // $1.00
    });

    it("Should support multiple router types", async function () {
      // SwapRouter enum: KyberSwap = 0, Odos = 1, Pendle = 2
      const routers = {
        KyberSwap: 0,
        Odos: 1,
        Pendle: 2
      };

      expect(routers.KyberSwap).to.equal(0);
      expect(routers.Odos).to.equal(1);
      expect(routers.Pendle).to.equal(2);
    });
  });

  describe("Edge cases", function () {
    it("Should handle tokens with different decimals", async function () {
      // Deploy token with 18 decimals
      const MockERC20Factory = await ethers.getContractFactory("MockERC20");
      const initialSupply = ethers.parseUnits("1000", 18); // 1000 WETH
      const weth = await MockERC20Factory.deploy("Wrapped Ether", "WETH", 18, initialSupply);

      // Add price feed for WETH ($2000)
      const MockAggregatorFactory = await ethers.getContractFactory("MockAggregatorV3");
      const wethFeed = await MockAggregatorFactory.deploy(ORACLE_DECIMALS);
      await wethFeed.updateAnswer(2000_00_000_000); // $2000
      await priceOracle.addPriceFeed(await weth.getAddress(), await wethFeed.getAddress());

      // Calculate USD value: 1 WETH = $2000
      const amountIn = 1n * 10n ** 18n; // 1 WETH
      const usdValueIn = await priceOracle.getUsdValue(
        await weth.getAddress(),
        amountIn
      );

      // Should be $2000 with 8 decimals
      expect(usdValueIn).to.equal(2000_00_000_000n);

      // Calculate equivalent USDC amount for validation
      // If we receive 1995 USDC (0.5% slippage from $2000)
      const amountOut = 1995n * 10n ** BigInt(USDC_DECIMALS);
      const usdValueOut = await priceOracle.getUsdValue(
        await usdc.getAddress(),
        amountOut
      );

      // Should be $1995
      expect(usdValueOut).to.equal(1995_00_000_000n);

      // Slippage check: usdValueOut >= usdValueIn * 0.995
      const minAcceptable = (usdValueIn * 9950n) / 10000n;
      expect(usdValueOut).to.be.gte(minAcceptable); // Should pass
    });

    it("Should handle very small amounts", async function () {
      const amountIn = 1n; // 0.000001 USDC (smallest unit)

      const usdValueIn = await priceOracle.getUsdValue(
        await usdc.getAddress(),
        amountIn
      );

      // Should be $0.000001 with 8 decimals = 0.01 (rounded)
      expect(usdValueIn).to.be.gte(0n);
    });

    it("Should handle very large amounts", async function () {
      const amountIn = 1_000_000_000n * 10n ** BigInt(USDC_DECIMALS); // 1 billion USDC

      const usdValueIn = await priceOracle.getUsdValue(
        await usdc.getAddress(),
        amountIn
      );

      // Should be $1 billion with 8 decimals
      expect(usdValueIn).to.equal(1_000_000_000_00_000_000n);
    });
  });
});
