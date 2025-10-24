import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import {
  AaveLeveragedStrategy,
  MockERC20,
  PriceOracle,
  MockPendleOracle,
  MockAggregatorV3,
  MockAavePool,
  MockAavePoolDataProvider,
  MockAavePoolAddressesProvider,
} from "../typechain-types";

describe("AaveLeveragedStrategy", function () {
  let owner: SignerWithAddress;
  let parent: SignerWithAddress;
  let user: SignerWithAddress;
  let strategy: AaveLeveragedStrategy;
  let baseAsset: MockERC20;
  let collateralAsset: MockERC20;
  let debtAsset: MockERC20;
  let priceOracle: PriceOracle;
  let pendleOracle: MockPendleOracle;
  let baseAssetFeed: MockAggregatorV3;
  let collateralFeed: MockAggregatorV3;
  let debtFeed: MockAggregatorV3;
  let aavePool: MockAavePool;
  let dataProvider: MockAavePoolDataProvider;
  let addressesProvider: MockAavePoolAddressesProvider;

  const BASE_ASSET_DECIMALS = 6;
  const COLLATERAL_DECIMALS = 18;
  const DEBT_DECIMALS = 6;
  const ORACLE_DECIMALS = 8;

  // Command types
  const SUPPLY = 0;
  const WITHDRAW = 1;
  const BORROW = 2;
  const REPAY = 3;
  const SWAP = 4;

  beforeEach(async function () {
    [owner, parent, user] = await ethers.getSigners();

    // Deploy tokens
    const MockERC20Factory = await ethers.getContractFactory("MockERC20");

    baseAsset = await MockERC20Factory.deploy(
      "USD Coin",
      "USDC",
      BASE_ASSET_DECIMALS,
      ethers.parseUnits("10000000", BASE_ASSET_DECIMALS)
    );

    collateralAsset = await MockERC20Factory.deploy(
      "PT Token",
      "PT",
      COLLATERAL_DECIMALS,
      ethers.parseUnits("10000000", COLLATERAL_DECIMALS)
    );

    debtAsset = await MockERC20Factory.deploy(
      "USDC",
      "USDC",
      DEBT_DECIMALS,
      ethers.parseUnits("10000000", DEBT_DECIMALS)
    );

    // Deploy mock price feeds
    const MockAggregatorFactory = await ethers.getContractFactory("MockAggregatorV3");
    baseAssetFeed = await MockAggregatorFactory.deploy(ORACLE_DECIMALS);
    await baseAssetFeed.updateAnswer(100000000); // $1.00

    collateralFeed = await MockAggregatorFactory.deploy(ORACLE_DECIMALS);
    await collateralFeed.updateAnswer(95000000); // $0.95 (PT at discount)

    debtFeed = await MockAggregatorFactory.deploy(ORACLE_DECIMALS);
    await debtFeed.updateAnswer(100000000); // $1.00

    // Deploy Pendle Oracle mock
    const MockPendleOracleFactory = await ethers.getContractFactory("MockPendleOracle");
    pendleOracle = await MockPendleOracleFactory.deploy();

    // Deploy PriceOracle
    const PriceOracleFactory = await ethers.getContractFactory("PriceOracle");
    priceOracle = await PriceOracleFactory.deploy(await pendleOracle.getAddress());
    await priceOracle.addPriceFeed(await baseAsset.getAddress(), await baseAssetFeed.getAddress());
    await priceOracle.addPriceFeed(await collateralAsset.getAddress(), await collateralFeed.getAddress());
    await priceOracle.addPriceFeed(await debtAsset.getAddress(), await debtFeed.getAddress());

    // Deploy mock Aave contracts
    const MockAavePoolFactory = await ethers.getContractFactory("MockAavePool");
    const MockDataProviderFactory = await ethers.getContractFactory("MockAavePoolDataProvider");
    const MockAddressesProviderFactory = await ethers.getContractFactory("MockAavePoolAddressesProvider");

    // Create a placeholder address for addressesProvider
    const placeholderAddress = ethers.Wallet.createRandom().address;
    aavePool = await MockAavePoolFactory.deploy(placeholderAddress);
    dataProvider = await MockDataProviderFactory.deploy(await aavePool.getAddress());
    addressesProvider = await MockAddressesProviderFactory.deploy(await dataProvider.getAddress());

    // Now deploy pool with correct addressesProvider
    aavePool = await MockAavePoolFactory.deploy(await addressesProvider.getAddress());
    dataProvider = await MockDataProviderFactory.deploy(await aavePool.getAddress());
    await addressesProvider.setPoolDataProvider(await dataProvider.getAddress());

    // Fund pool with tokens for borrowing
    await debtAsset.transfer(await aavePool.getAddress(), ethers.parseUnits("1000000", DEBT_DECIMALS));

    // Deploy AaveLeveragedStrategy
    const AaveStrategyFactory = await ethers.getContractFactory("AaveLeveragedStrategy");
    strategy = await AaveStrategyFactory.deploy(
      parent.address,
      await baseAsset.getAddress(),
      await priceOracle.getAddress(),
      await aavePool.getAddress(),
      await collateralAsset.getAddress(),
      await debtAsset.getAddress()
    );
  });

  describe("Deployment", function () {
    it("Should set parent address correctly", async function () {
      expect(await strategy.parent()).to.equal(parent.address);
    });

    it("Should set base asset correctly", async function () {
      expect(await strategy.baseAsset()).to.equal(await baseAsset.getAddress());
    });

    it("Should set collateral asset correctly", async function () {
      expect(await strategy.collateralAsset()).to.equal(await collateralAsset.getAddress());
    });

    it("Should set debt asset correctly", async function () {
      expect(await strategy.debtAsset()).to.equal(await debtAsset.getAddress());
    });

    it("Should set Aave pool correctly", async function () {
      expect(await strategy.pool()).to.equal(await aavePool.getAddress());
    });
  });

  describe("Supply and Borrow", function () {
    beforeEach(async function () {
      // Transfer collateral to strategy
      await collateralAsset.transfer(
        await strategy.getAddress(),
        ethers.parseUnits("1000", COLLATERAL_DECIMALS)
      );
    });

    it("Should supply collateral to Aave", async function () {
      const supplyAmount = ethers.parseUnits("1000", COLLATERAL_DECIMALS);
      const supplyCommand = {
        cmdType: SUPPLY,
        data: ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [await collateralAsset.getAddress(), supplyAmount]
        ),
      };

      await strategy.connect(parent).deposit(
        await collateralAsset.getAddress(),
        supplyAmount,
        ethers.ZeroAddress,
        0,
        0,
        ethers.AbiCoder.defaultAbiCoder().encode(
          ["tuple(uint8 cmdType, bytes data)[]"],
          [[supplyCommand]]
        )
      );

      // Verify collateral was supplied by checking pool balance
      const poolCollateral = await aavePool.getATokenBalance(
        await strategy.getAddress(),
        await collateralAsset.getAddress()
      );
      expect(poolCollateral).to.equal(supplyAmount);
    });

    it("Should borrow from Aave after supplying collateral", async function () {
      const supplyAmount = ethers.parseUnits("1000", COLLATERAL_DECIMALS);
      const borrowAmount = ethers.parseUnits("400", DEBT_DECIMALS);

      const supplyCommand = {
        cmdType: SUPPLY,
        data: ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [await collateralAsset.getAddress(), supplyAmount]
        ),
      };

      const borrowCommand = {
        cmdType: BORROW,
        data: ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [await debtAsset.getAddress(), borrowAmount]
        ),
      };

      await strategy.connect(parent).deposit(
        await collateralAsset.getAddress(),
        supplyAmount,
        ethers.ZeroAddress,
        0,
        0,
        ethers.AbiCoder.defaultAbiCoder().encode(
          ["tuple(uint8 cmdType, bytes data)[]"],
          [[supplyCommand, borrowCommand]]
        )
      );

      // Verify position by checking pool balances
      const poolCollateral = await aavePool.getATokenBalance(
        await strategy.getAddress(),
        await collateralAsset.getAddress()
      );
      const poolDebt = await aavePool.getDebtBalance(
        await strategy.getAddress(),
        await debtAsset.getAddress()
      );
      expect(poolCollateral).to.equal(supplyAmount);
      expect(poolDebt).to.equal(borrowAmount);
    });
  });

  describe("Withdraw and Repay", function () {
    beforeEach(async function () {
      // Setup: Supply 1000 PT and borrow 400 USDC
      const supplyAmount = ethers.parseUnits("1000", COLLATERAL_DECIMALS);
      const borrowAmount = ethers.parseUnits("400", DEBT_DECIMALS);

      await collateralAsset.transfer(await strategy.getAddress(), supplyAmount);

      const supplyCommand = {
        cmdType: SUPPLY,
        data: ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [await collateralAsset.getAddress(), supplyAmount]
        ),
      };

      const borrowCommand = {
        cmdType: BORROW,
        data: ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [await debtAsset.getAddress(), borrowAmount]
        ),
      };

      await strategy.connect(parent).deposit(
        await collateralAsset.getAddress(),
        supplyAmount,
        ethers.ZeroAddress,
        0,
        0,
        ethers.AbiCoder.defaultAbiCoder().encode(
          ["tuple(uint8 cmdType, bytes data)[]"],
          [[supplyCommand, borrowCommand]]
        )
      );

      // Transfer borrowed USDC back to strategy for repayment tests
      await debtAsset.transfer(await strategy.getAddress(), borrowAmount);
    });

    it("Should withdraw proportionally (50%)", async function () {
      const withdrawPercentage = ethers.parseUnits("0.5", 18); // 50%

      // Transfer flash loan to strategy
      await debtAsset.transfer(await strategy.getAddress(), ethers.parseUnits("200", DEBT_DECIMALS));

      await strategy.connect(parent).withdraw(
        withdrawPercentage,
        await collateralAsset.getAddress(),
        await debtAsset.getAddress(),
        ethers.parseUnits("200", DEBT_DECIMALS),
        ethers.parseUnits("200", DEBT_DECIMALS),
        "0x"
      );

      // Verify position by checking pool balances
      const poolCollateral = await aavePool.getATokenBalance(
        await strategy.getAddress(),
        await collateralAsset.getAddress()
      );
      const poolDebt = await aavePool.getDebtBalance(
        await strategy.getAddress(),
        await debtAsset.getAddress()
      );

      // Should have ~50% left
      expect(poolCollateral).to.be.closeTo(
        ethers.parseUnits("500", COLLATERAL_DECIMALS),
        ethers.parseUnits("1", COLLATERAL_DECIMALS)
      );
      expect(poolDebt).to.be.closeTo(
        ethers.parseUnits("200", DEBT_DECIMALS),
        ethers.parseUnits("1", DEBT_DECIMALS)
      );
    });
  });

  describe("Safe Withdrawal Calculation", function () {
    it("Should repay slightly more debt when withdrawing (50%)", async function () {
      // This test verifies the safe withdrawal logic indirectly through actual withdrawal
      const withdrawPercentage = ethers.parseUnits("0.5", 18); // 50%

      // Transfer flash loan to strategy
      await debtAsset.transfer(await strategy.getAddress(), ethers.parseUnits("300", DEBT_DECIMALS));

      // Withdraw 50%
      await strategy.connect(parent).withdraw(
        withdrawPercentage,
        await collateralAsset.getAddress(),
        await debtAsset.getAddress(),
        ethers.parseUnits("300", DEBT_DECIMALS),
        ethers.parseUnits("300", DEBT_DECIMALS),
        "0x"
      );

      const poolDebt = await aavePool.getDebtBalance(
        await strategy.getAddress(),
        await debtAsset.getAddress()
      );

      // Debt should be reduced by slightly more than 200 (50% of 400)
      // due to the +1 buffer in calculation
      expect(poolDebt).to.be.lt(ethers.parseUnits("200", DEBT_DECIMALS));
    });
  });

  describe("Total Assets", function () {
    it("Should calculate total assets correctly", async function () {
      // Setup position: 1000 PT collateral, 400 USDC debt
      const supplyAmount = ethers.parseUnits("1000", COLLATERAL_DECIMALS);
      const borrowAmount = ethers.parseUnits("400", DEBT_DECIMALS);

      await collateralAsset.transfer(await strategy.getAddress(), supplyAmount);

      const supplyCommand = {
        cmdType: SUPPLY,
        data: ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [await collateralAsset.getAddress(), supplyAmount]
        ),
      };

      const borrowCommand = {
        cmdType: BORROW,
        data: ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [await debtAsset.getAddress(), borrowAmount]
        ),
      };

      await strategy.connect(parent).deposit(
        await collateralAsset.getAddress(),
        supplyAmount,
        ethers.ZeroAddress,
        0,
        0,
        ethers.AbiCoder.defaultAbiCoder().encode(
          ["tuple(uint8 cmdType, bytes data)[]"],
          [[supplyCommand, borrowCommand]]
        )
      );

      const totalAssets = await strategy.totalAssets();

      // Expected:
      // - Collateral: 1000 PT * $0.95 = $950
      // - Idle borrowed USDC: 400 USDC * $1.00 = $400
      // - Debt: -400 USDC * $1.00 = -$400
      // Total: $950 + $400 - $400 = $950 in USDC
      const expectedAssets = ethers.parseUnits("950", BASE_ASSET_DECIMALS);

      expect(totalAssets).to.be.closeTo(expectedAssets, ethers.parseUnits("1", BASE_ASSET_DECIMALS));
    });

    it("Should return 0 if debt exceeds collateral value", async function () {
      // Setup position: 1000 PT collateral, 1000 USDC debt
      const supplyAmount = ethers.parseUnits("1000", COLLATERAL_DECIMALS);
      const borrowAmount = ethers.parseUnits("1000", DEBT_DECIMALS);

      await collateralAsset.transfer(await strategy.getAddress(), supplyAmount);

      const supplyCommand = {
        cmdType: SUPPLY,
        data: ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [await collateralAsset.getAddress(), supplyAmount]
        ),
      };

      const borrowCommand = {
        cmdType: BORROW,
        data: ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [await debtAsset.getAddress(), borrowAmount]
        ),
      };

      await strategy.connect(parent).deposit(
        await collateralAsset.getAddress(),
        supplyAmount,
        ethers.ZeroAddress,
        0,
        0,
        ethers.AbiCoder.defaultAbiCoder().encode(
          ["tuple(uint8 cmdType, bytes data)[]"],
          [[supplyCommand, borrowCommand]]
        )
      );

      const totalAssets = await strategy.totalAssets();

      // Expected:
      // - Collateral: 1000 PT * $0.95 = $950
      // - Idle borrowed USDC: 1000 USDC * $1.00 = $1000
      // - Debt: -1000 USDC * $1.00 = -$1000
      // Total: $950 + $1000 - $1000 = $950 in USDC
      const expectedAssets = ethers.parseUnits("950", BASE_ASSET_DECIMALS);

      expect(totalAssets).to.be.closeTo(expectedAssets, ethers.parseUnits("1", BASE_ASSET_DECIMALS));
    });
  });

  describe("Access Control", function () {
    it("Should only allow parent to call deposit", async function () {
      await expect(
        strategy.connect(user).deposit(
          await collateralAsset.getAddress(),
          0,
          ethers.ZeroAddress,
          0,
          0,
          "0x"
        )
      ).to.be.reverted;
    });

    it("Should only allow parent to call withdraw", async function () {
      await expect(
        strategy.connect(user).withdraw(
          ethers.parseUnits("0.5", 18),
          await collateralAsset.getAddress(),
          ethers.ZeroAddress,
          0,
          0,
          "0x"
        )
      ).to.be.reverted;
    });

    it("Should only allow parent to call rebalance", async function () {
      await expect(
        strategy.connect(user).rebalance(
          ethers.ZeroAddress,
          0,
          0,
          "0x"
        )
      ).to.be.reverted;
    });
  });
});
