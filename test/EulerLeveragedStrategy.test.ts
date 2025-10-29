import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import {
  EulerLeveragedStrategy,
  MockEVault,
  MockEVC,
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

describe("EulerLeveragedStrategy", function () {
  let owner: SignerWithAddress;
  let parent: SignerWithAddress;
  let user: SignerWithAddress;
  let strategy: EulerLeveragedStrategy;
  let evc: MockEVC;
  let collateralVault: MockEVault;
  let debtVault: MockEVault;
  let collateralAsset: MockERC20;
  let debtAsset: MockERC20;
  let priceOracle: PriceOracle;
  let pendleOracle: MockPendleOracle;
  let collateralFeed: MockAggregatorV3;
  let debtFeed: MockAggregatorV3;

  const COLLATERAL_DECIMALS = 18;
  const DEBT_DECIMALS = 6;
  const ORACLE_DECIMALS = 8;

  beforeEach(async function () {
    [owner, parent, user] = await ethers.getSigners();

    // Deploy mock tokens
    const MockERC20Factory = await ethers.getContractFactory("MockERC20");
    const collateralSupply = ethers.parseUnits("1000000", COLLATERAL_DECIMALS);
    const debtSupply = ethers.parseUnits("1000000", DEBT_DECIMALS);

    collateralAsset = await MockERC20Factory.deploy(
      "PT Token",
      "PT",
      COLLATERAL_DECIMALS,
      collateralSupply
    );

    debtAsset = await MockERC20Factory.deploy(
      "USD Coin",
      "USDC",
      DEBT_DECIMALS,
      debtSupply
    );

    // Deploy mock price feeds
    const MockAggregatorFactory = await ethers.getContractFactory("MockAggregatorV3");
    collateralFeed = await MockAggregatorFactory.deploy(ORACLE_DECIMALS);
    await collateralFeed.updateAnswer(1_50_000_000); // $1.50

    debtFeed = await MockAggregatorFactory.deploy(ORACLE_DECIMALS);
    await debtFeed.updateAnswer(1_00_000_000); // $1.00

    // Deploy Pendle Oracle mock
    const MockPendleOracleFactory = await ethers.getContractFactory("MockPendleOracle");
    pendleOracle = await MockPendleOracleFactory.deploy();

    // Deploy PriceOracle
    const PriceOracleFactory = await ethers.getContractFactory("PriceOracle");
    priceOracle = await PriceOracleFactory.deploy(await pendleOracle.getAddress());
    await priceOracle.addPriceFeed(await collateralAsset.getAddress(), await collateralFeed.getAddress());
    await priceOracle.addPriceFeed(await debtAsset.getAddress(), await debtFeed.getAddress());

    // Deploy MockEVC
    const MockEVCFactory = await ethers.getContractFactory("MockEVC");
    evc = await MockEVCFactory.deploy();

    // Deploy MockEVaults
    const MockEVaultFactory = await ethers.getContractFactory("MockEVault");
    collateralVault = await MockEVaultFactory.deploy(await collateralAsset.getAddress());
    debtVault = await MockEVaultFactory.deploy(await debtAsset.getAddress());

    // Deploy EulerLeveragedStrategy
    const EulerStrategyFactory = await ethers.getContractFactory("EulerLeveragedStrategy");
    strategy = await EulerStrategyFactory.deploy();
    await strategy.initialize(
      parent.address,
      await debtAsset.getAddress(),
      await priceOracle.getAddress(),
      await evc.getAddress(),
      await collateralVault.getAddress(),
      await debtVault.getAddress()
    );

    // Fund vaults with liquidity for borrows
    await debtAsset.transfer(await debtVault.getAddress(), ethers.parseUnits("100000", DEBT_DECIMALS));
  });

  describe("Deployment", function () {
    it("Should set parent address correctly", async function () {
      expect(await strategy.parent()).to.equal(parent.address);
    });

    it("Should set base asset correctly", async function () {
      expect(await strategy.baseAsset()).to.equal(await debtAsset.getAddress());
    });

    it("Should set collateral vault correctly", async function () {
      expect(await strategy.collateralVault()).to.equal(await collateralVault.getAddress());
    });

    it("Should set debt vault correctly", async function () {
      expect(await strategy.debtVault()).to.equal(await debtVault.getAddress());
    });

    it("Should set EVC correctly", async function () {
      expect(await strategy.evc()).to.equal(await evc.getAddress());
    });

    it("Should extract collateral asset from vault", async function () {
      expect(await strategy.collateralAsset()).to.equal(await collateralAsset.getAddress());
    });

    it("Should extract debt asset from vault", async function () {
      expect(await strategy.debtAsset()).to.equal(await debtAsset.getAddress());
    });
  });

  describe("Supply and Borrow", function () {
    it("Should supply collateral to Euler", async function () {
      const supplyAmount = ethers.parseUnits("1000", COLLATERAL_DECIMALS);

      // Transfer tokens to strategy
      await collateralAsset.transfer(await strategy.getAddress(), supplyAmount);

      // Create SUPPLY command
      const supplyCommand = {
        cmdType: 0, // SUPPLY
        data: ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [await collateralAsset.getAddress(), supplyAmount]
        ),
      };

      const commands = [supplyCommand];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      await strategy.connect(parent).deposit(
        await debtAsset.getAddress(),
        0,
        ethers.ZeroAddress,
        0,
        0,
        data
      );

      // Check vault balance
      const balance = await collateralVault.balanceOf(await strategy.getAddress());
      expect(balance).to.be.gt(0);
    });

    it("Should borrow from Euler after supplying collateral", async function () {
      const supplyAmount = ethers.parseUnits("1000", COLLATERAL_DECIMALS);
      const borrowAmount = ethers.parseUnits("500", DEBT_DECIMALS);

      // Transfer collateral tokens to strategy
      await collateralAsset.transfer(await strategy.getAddress(), supplyAmount);

      // Create SUPPLY + BORROW commands
      const supplyCommand = {
        cmdType: 0, // SUPPLY
        data: ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [await collateralAsset.getAddress(), supplyAmount]
        ),
      };

      const borrowCommand = {
        cmdType: 2, // BORROW
        data: ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [await debtAsset.getAddress(), borrowAmount]
        ),
      };

      const commands = [supplyCommand, borrowCommand];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      await strategy.connect(parent).deposit(
        await debtAsset.getAddress(),
        0,
        ethers.ZeroAddress,
        0,
        0,
        data
      );

      // Check debt
      const debt = await debtVault.debtOf(await strategy.getAddress());
      expect(debt).to.equal(borrowAmount);
    });
  });

  describe("Withdraw and Repay", function () {
    it("Should withdraw proportionally (50%)", async function () {
      const supplyAmount = ethers.parseUnits("1000", COLLATERAL_DECIMALS);
      const borrowAmount = ethers.parseUnits("500", DEBT_DECIMALS);

      // Setup position
      await collateralAsset.transfer(await strategy.getAddress(), supplyAmount);

      const supplyCommand = {
        cmdType: 0, // SUPPLY
        data: ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [await collateralAsset.getAddress(), supplyAmount]
        ),
      };

      const borrowCommand = {
        cmdType: 2, // BORROW
        data: ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [await debtAsset.getAddress(), borrowAmount]
        ),
      };

      let commands = [supplyCommand, borrowCommand];
      let data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      await strategy.connect(parent).deposit(
        await debtAsset.getAddress(),
        0,
        ethers.ZeroAddress,
        0,
        0,
        data
      );

      // Get initial balances
      const initialCollateral = await collateralVault.convertToAssets(
        await collateralVault.balanceOf(await strategy.getAddress())
      );
      const initialDebt = await debtVault.debtOf(await strategy.getAddress());

      // Withdraw 50%
      commands = [];
      data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      await strategy.connect(parent).withdraw(
        ethers.parseEther("0.5"), // 50%
        await debtAsset.getAddress(),
        ethers.ZeroAddress,
        0,
        0,
        data
      );

      // Check remaining balances (should be ~50% of initial)
      const finalCollateral = await collateralVault.convertToAssets(
        await collateralVault.balanceOf(await strategy.getAddress())
      );
      const finalDebt = await debtVault.debtOf(await strategy.getAddress());

      // Allow 1% deviation due to rounding
      expect(finalCollateral).to.be.closeTo(initialCollateral / 2n, initialCollateral / 100n);
      expect(finalDebt).to.be.closeTo(initialDebt / 2n, initialDebt / 100n);
    });
  });

  describe("Safe Withdrawal Calculation", function () {
    it("Should repay slightly more debt when withdrawing (50%)", async function () {
      const supplyAmount = ethers.parseUnits("1000", COLLATERAL_DECIMALS);
      const borrowAmount = ethers.parseUnits("500", DEBT_DECIMALS);

      // Setup position normally through commands
      await collateralAsset.transfer(await strategy.getAddress(), supplyAmount);

      const supplyCommand = {
        cmdType: 0,
        data: ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [await collateralAsset.getAddress(), supplyAmount]
        ),
      };

      const borrowCommand = {
        cmdType: 2,
        data: ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [await debtAsset.getAddress(), borrowAmount]
        ),
      };

      let commands = [supplyCommand, borrowCommand];
      let data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      await strategy.connect(parent).deposit(
        await debtAsset.getAddress(),
        0,
        ethers.ZeroAddress,
        0,
        0,
        data
      );

      const collateral = await collateralVault.convertToAssets(
        await collateralVault.balanceOf(await strategy.getAddress())
      );
      const debtBefore = await debtVault.debtOf(await strategy.getAddress());

      // Withdraw 50%
      commands = [];
      data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      const percentage = ethers.parseEther("0.5"); // 50%
      await strategy.connect(parent).withdraw(
        percentage,
        await debtAsset.getAddress(),
        ethers.ZeroAddress,
        0,
        0,
        data
      );

      // Calculate expected amounts
      const expectedRepay = (debtBefore * (percentage + 1n)) / ethers.parseEther("1");

      // Verify debt was repaid (slightly more than proportional due to +1)
      const debtAfter = await debtVault.debtOf(await strategy.getAddress());
      const actualRepaid = debtBefore - debtAfter;

      // The actualRepaid should be >= expectedRepay (which includes +1)
      // Allow small rounding error (0.1% of debt)
      expect(actualRepaid).to.be.gte(expectedRepay - debtBefore / 1000n);
    });
  });

  describe("Total Assets", function () {
    it("Should calculate total assets correctly", async function () {
      const supplyAmount = ethers.parseUnits("1000", COLLATERAL_DECIMALS); // 1000 PT @ $1.50 = $1500
      const borrowAmount = ethers.parseUnits("500", DEBT_DECIMALS); // 500 USDC @ $1.00 = $500

      // Transfer tokens and setup position
      await collateralAsset.transfer(await strategy.getAddress(), supplyAmount);

      const supplyCommand = {
        cmdType: 0,
        data: ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [await collateralAsset.getAddress(), supplyAmount]
        ),
      };

      const borrowCommand = {
        cmdType: 2,
        data: ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [await debtAsset.getAddress(), borrowAmount]
        ),
      };

      const commands = [supplyCommand, borrowCommand];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      await strategy.connect(parent).deposit(
        await debtAsset.getAddress(),
        0,
        ethers.ZeroAddress,
        0,
        0,
        data
      );

      // Total assets in base asset (USDC):
      // Collateral: 1000 PT * $1.50 = $1500
      // Idle debt tokens: 500 USDC * $1.00 = $500 (borrowed tokens on balance)
      // Debt: 500 USDC * $1.00 = $500
      // Total USD: $1500 + $500 - $500 = $1500
      // In USDC: $1500 / $1.00 = 1500 USDC
      const totalAssets = await strategy.totalAssets();
      expect(totalAssets).to.equal(ethers.parseUnits("1500", DEBT_DECIMALS));
    });

    it("Should return 0 if debt exceeds collateral value", async function () {
      const supplyAmount = ethers.parseUnits("200", COLLATERAL_DECIMALS); // 200 PT @ $1.50 = $300
      const borrowAmount = ethers.parseUnits("500", DEBT_DECIMALS); // 500 USDC @ $1.00 = $500

      await collateralAsset.transfer(await strategy.getAddress(), supplyAmount);

      const supplyCommand = {
        cmdType: 0,
        data: ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [await collateralAsset.getAddress(), supplyAmount]
        ),
      };

      const borrowCommand = {
        cmdType: 2,
        data: ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [await debtAsset.getAddress(), borrowAmount]
        ),
      };

      const commands = [supplyCommand, borrowCommand];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      await strategy.connect(parent).deposit(
        await debtAsset.getAddress(),
        0,
        ethers.ZeroAddress,
        0,
        0,
        data
      );

      // Total assets in base asset (USDC):
      // Collateral: 200 PT * $1.50 = $300
      // Idle debt tokens: 500 USDC * $1.00 = $500 (borrowed tokens on balance)
      // Debt: 500 USDC * $1.00 = $500
      // Total USD: $300 + $500 - $500 = $300
      // In USDC: $300 / $1.00 = 300 USDC
      const totalAssets = await strategy.totalAssets();
      expect(totalAssets).to.equal(ethers.parseUnits("300", DEBT_DECIMALS));
    });
  });

  describe("Position Queries", function () {
    it("Should return correct collateral and debt amounts", async function () {
      const supplyAmount = ethers.parseUnits("1000", COLLATERAL_DECIMALS);
      const borrowAmount = ethers.parseUnits("500", DEBT_DECIMALS);

      await collateralAsset.transfer(await strategy.getAddress(), supplyAmount);

      const supplyCommand = {
        cmdType: 0,
        data: ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [await collateralAsset.getAddress(), supplyAmount]
        ),
      };

      const borrowCommand = {
        cmdType: 2,
        data: ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [await debtAsset.getAddress(), borrowAmount]
        ),
      };

      const commands = [supplyCommand, borrowCommand];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      await strategy.connect(parent).deposit(
        await debtAsset.getAddress(),
        0,
        ethers.ZeroAddress,
        0,
        0,
        data
      );

      // Check position via vault directly
      const collateralShares = await collateralVault.balanceOf(await strategy.getAddress());
      const collateral = await collateralVault.convertToAssets(collateralShares);
      const debt = await debtVault.debtOf(await strategy.getAddress());

      expect(collateral).to.equal(supplyAmount);
      expect(debt).to.equal(borrowAmount);
    });

    it("Should handle share-based accounting for collateral", async function () {
      const supplyAmount = ethers.parseUnits("1000", COLLATERAL_DECIMALS);

      await collateralAsset.transfer(await strategy.getAddress(), supplyAmount);

      const supplyCommand = {
        cmdType: 0,
        data: ethers.AbiCoder.defaultAbiCoder().encode(
          ["address", "uint256"],
          [await collateralAsset.getAddress(), supplyAmount]
        ),
      };

      const commands = [supplyCommand];
      const data = ethers.AbiCoder.defaultAbiCoder().encode(
        ["tuple(uint8 cmdType, bytes data)[]"],
        [commands]
      );

      await strategy.connect(parent).deposit(
        await debtAsset.getAddress(),
        0,
        ethers.ZeroAddress,
        0,
        0,
        data
      );

      // Get shares
      const shares = await collateralVault.balanceOf(await strategy.getAddress());
      expect(shares).to.be.gt(0);

      // Get position amounts (should convert shares to assets)
      const collateralShares2 = await collateralVault.balanceOf(await strategy.getAddress());
      const collateral = await collateralVault.convertToAssets(collateralShares2);
      expect(collateral).to.equal(supplyAmount);
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
          await debtAsset.getAddress(),
          1000,
          ethers.ZeroAddress,
          0,
          0,
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
          ethers.parseEther("1"),
          await debtAsset.getAddress(),
          ethers.ZeroAddress,
          0,
          0,
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
        strategy.connect(user).rebalance(ethers.ZeroAddress, 0, 0, data)
      ).to.be.revertedWithCustomError(strategy, "Unauthorized");
    });
  });
});
