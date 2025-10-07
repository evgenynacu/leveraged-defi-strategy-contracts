import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers"
import { expect } from "chai"
import hre from "hardhat"

describe("PriceOracle", function () {
	// Constants
	const DECIMALS = 8;

	// Test fixture
	async function deployOracleFixture() {
		const [deployer, user1, user2] = await hre.ethers.getSigners();

		// Deploy mock Chainlink price feed
		const MockAggregatorFactory = await hre.ethers.getContractFactory("MockAggregatorV3");
		const usdcPriceFeed = await MockAggregatorFactory.deploy(8, 100000000); // $1.00
		const usdtPriceFeed = await MockAggregatorFactory.deploy(8, 99800000);  // $0.998

		// Deploy mock Pendle oracle
		const MockPendleOracleFactory = await hre.ethers.getContractFactory("MockPendleOracle");
		const mockPendleOracle = await MockPendleOracleFactory.deploy();

		// Deploy mock ERC20 tokens
		const MockERC20Factory = await hre.ethers.getContractFactory("MockERC20");
		const usdc = await MockERC20Factory.deploy("USD Coin", "USDC", 6, hre.ethers.parseUnits("1000000", 6));
		const usdt = await MockERC20Factory.deploy("Tether USD", "USDT", 6, hre.ethers.parseUnits("1000000", 6));
		// PT token must have same decimals as underlying (USDC = 6 decimals)
		const ptToken = await MockERC20Factory.deploy("PT Token", "PT", 6, hre.ethers.parseUnits("1000000", 6));

		// Deploy PriceOracle
		const PriceOracleFactory = await hre.ethers.getContractFactory("PriceOracle");
		const oracle = await PriceOracleFactory.deploy(await mockPendleOracle.getAddress());

		return {
			oracle,
			usdcPriceFeed,
			usdtPriceFeed,
			mockPendleOracle,
			usdc,
			usdt,
			ptToken,
			deployer,
			user1,
			user2,
		};
	}

	describe("Deployment & Initialization", function () {
		it("Should deploy with correct Pendle oracle address", async function () {
			const { oracle, mockPendleOracle } = await loadFixture(deployOracleFixture);

			expect(await oracle.pendleOracle()).to.equal(await mockPendleOracle.getAddress());
		});

		it("Should not allow zero address for Pendle oracle", async function () {
			const PriceOracleFactory = await hre.ethers.getContractFactory("PriceOracle");

			await expect(
				PriceOracleFactory.deploy(hre.ethers.ZeroAddress)
			).to.be.revertedWithCustomError(PriceOracleFactory, "InvalidToken");
		});

		it("Should set correct decimals constant", async function () {
			const { oracle } = await loadFixture(deployOracleFixture);

			expect(await oracle.DECIMALS()).to.equal(DECIMALS);
		});
	});

	describe("Price Feed Management", function () {
		it("Should allow owner to add price feed", async function () {
			const { oracle, usdc, usdcPriceFeed, deployer } = await loadFixture(deployOracleFixture);

			await expect(
				oracle.connect(deployer).addPriceFeed(
					await usdc.getAddress(),
					await usdcPriceFeed.getAddress()
				)
			).to.emit(oracle, "PriceFeedUpdated")
				.withArgs(await usdc.getAddress(), await usdcPriceFeed.getAddress());

			expect(await oracle.getPriceFeed(await usdc.getAddress())).to.equal(
				await usdcPriceFeed.getAddress()
			);
		});

		it("Should not allow non-owner to add price feed", async function () {
			const { oracle, usdc, usdcPriceFeed, user1 } = await loadFixture(deployOracleFixture);

			await expect(
				oracle.connect(user1).addPriceFeed(
					await usdc.getAddress(),
					await usdcPriceFeed.getAddress()
				)
			).to.be.revertedWithCustomError(oracle, "OwnableUnauthorizedAccount");
		});

		it("Should not allow zero token address", async function () {
			const { oracle, usdcPriceFeed } = await loadFixture(deployOracleFixture);

			await expect(
				oracle.addPriceFeed(
					hre.ethers.ZeroAddress,
					await usdcPriceFeed.getAddress()
				)
			).to.be.revertedWithCustomError(oracle, "InvalidToken");
		});

		it("Should not allow zero price feed address", async function () {
			const { oracle, usdc } = await loadFixture(deployOracleFixture);

			await expect(
				oracle.addPriceFeed(
					await usdc.getAddress(),
					hre.ethers.ZeroAddress
				)
			).to.be.revertedWithCustomError(oracle, "InvalidPriceFeed");
		});

		it("Should allow updating existing price feed", async function () {
			const { oracle, usdc, usdcPriceFeed, usdtPriceFeed } = await loadFixture(deployOracleFixture);

			// Add initial price feed
			await oracle.addPriceFeed(
				await usdc.getAddress(),
				await usdcPriceFeed.getAddress()
			);

			// Update to new price feed
			await oracle.addPriceFeed(
				await usdc.getAddress(),
				await usdtPriceFeed.getAddress()
			);

			expect(await oracle.getPriceFeed(await usdc.getAddress())).to.equal(
				await usdtPriceFeed.getAddress()
			);
		});
	});

	describe("PT Token Management", function () {
		it("Should allow owner to add PT token", async function () {
			const { oracle, ptToken, usdc, usdcPriceFeed } = await loadFixture(deployOracleFixture);

			// First add price feed for underlying
			await oracle.addPriceFeed(await usdc.getAddress(), await usdcPriceFeed.getAddress());

			const mockMarket = "0x1234567890123456789012345678901234567890";

			await expect(
				oracle.addPTToken(
					await ptToken.getAddress(),
					mockMarket,
					false, // useSy = false (use asset rate)
					await usdc.getAddress()
				)
			).to.emit(oracle, "PTTokenAdded")
				.withArgs(await ptToken.getAddress(), mockMarket, await usdc.getAddress());

			expect(await oracle.getPTMarket(await ptToken.getAddress())).to.equal(mockMarket);
			expect(await oracle.isPTToken(await ptToken.getAddress())).to.be.true;
		});

		it("Should not allow adding PT token without underlying price feed", async function () {
			const { oracle, ptToken, usdc } = await loadFixture(deployOracleFixture);

			const mockMarket = "0x1234567890123456789012345678901234567890";

			await expect(
				oracle.addPTToken(
					await ptToken.getAddress(),
					mockMarket,
					false,
					await usdc.getAddress() // USDC doesn't have price feed yet
				)
			).to.be.revertedWithCustomError(oracle, "UnderlyingMissingPriceFeed");
		});

		it("Should not allow zero PT token address", async function () {
			const { oracle, usdc, usdcPriceFeed } = await loadFixture(deployOracleFixture);

			await oracle.addPriceFeed(await usdc.getAddress(), await usdcPriceFeed.getAddress());

			const mockMarket = "0x1234567890123456789012345678901234567890";

			await expect(
				oracle.addPTToken(
					hre.ethers.ZeroAddress,
					mockMarket,
					false,
					await usdc.getAddress()
				)
			).to.be.revertedWithCustomError(oracle, "InvalidToken");
		});

		it("Should not allow zero market address", async function () {
			const { oracle, ptToken, usdc, usdcPriceFeed } = await loadFixture(deployOracleFixture);

			await oracle.addPriceFeed(await usdc.getAddress(), await usdcPriceFeed.getAddress());

			await expect(
				oracle.addPTToken(
					await ptToken.getAddress(),
					hre.ethers.ZeroAddress,
					false,
					await usdc.getAddress()
				)
			).to.be.revertedWithCustomError(oracle, "InvalidMarket");
		});

		it("Should not allow zero underlying address", async function () {
			const { oracle, ptToken } = await loadFixture(deployOracleFixture);

			const mockMarket = "0x1234567890123456789012345678901234567890";

			await expect(
				oracle.addPTToken(
					await ptToken.getAddress(),
					mockMarket,
					false,
					hre.ethers.ZeroAddress
				)
			).to.be.revertedWithCustomError(oracle, "InvalidUnderlying");
		});
	});

	describe("Get USD Value - Standard Tokens", function () {
		it("Should calculate USD value correctly for standard token", async function () {
			const { oracle, usdc, usdcPriceFeed } = await loadFixture(deployOracleFixture);

			await oracle.addPriceFeed(await usdc.getAddress(), await usdcPriceFeed.getAddress());

			const amount = hre.ethers.parseUnits("1000", 6); // 1000 USDC (6 decimals)
			const usdValue = await oracle.getUsdValue(await usdc.getAddress(), amount);

			// Expected: 1000 USDC * $1.00 = $1000.00 (8 decimals)
			expect(usdValue).to.equal(100000000000n); // $1000 with 8 decimals
		});

		it("Should handle different token decimals correctly", async function () {
			const { oracle, usdt, usdtPriceFeed } = await loadFixture(deployOracleFixture);

			await oracle.addPriceFeed(await usdt.getAddress(), await usdtPriceFeed.getAddress());

			const amount = hre.ethers.parseUnits("500", 6); // 500 USDT (6 decimals)
			const usdValue = await oracle.getUsdValue(await usdt.getAddress(), amount);

			// Expected: 500 USDT * $0.998 = $499.00 (8 decimals)
			expect(usdValue).to.equal(49900000000n); // $499 with 8 decimals
		});

		it("Should revert for token without price feed", async function () {
			const { oracle, usdc } = await loadFixture(deployOracleFixture);

			const amount = hre.ethers.parseUnits("1000", 6);

			await expect(
				oracle.getUsdValue(await usdc.getAddress(), amount)
			).to.be.revertedWithCustomError(oracle, "PriceFeedNotFound");
		});

		it("Should revert for zero token address", async function () {
			const { oracle } = await loadFixture(deployOracleFixture);

			await expect(
				oracle.getUsdValue(hre.ethers.ZeroAddress, 1000)
			).to.be.revertedWithCustomError(oracle, "InvalidToken");
		});

		it("Should return zero for zero amount", async function () {
			const { oracle, usdc, usdcPriceFeed } = await loadFixture(deployOracleFixture);

			await oracle.addPriceFeed(await usdc.getAddress(), await usdcPriceFeed.getAddress());

			expect(await oracle.getUsdValue(await usdc.getAddress(), 0)).to.equal(0n);
		});

		it("Should revert for stale price data", async function () {
			const { oracle, usdc } = await loadFixture(deployOracleFixture);

			// Deploy stale price feed (updated more than 24 hours ago)
			const MockAggregatorFactory = await hre.ethers.getContractFactory("MockAggregatorV3");
			const stalePriceFeed = await MockAggregatorFactory.deploy(8, 100000000);

			// Set timestamp to 25 hours ago
			await stalePriceFeed.setUpdatedAt(Math.floor(Date.now() / 1000) - (25 * 3600));

			await oracle.addPriceFeed(await usdc.getAddress(), await stalePriceFeed.getAddress());

			const amount = hre.ethers.parseUnits("1000", 6);

			await expect(
				oracle.getUsdValue(await usdc.getAddress(), amount)
			).to.be.revertedWithCustomError(oracle, "PriceDataTooOld");
		});

		it("Should revert for invalid price (zero or negative)", async function () {
			const { oracle, usdc } = await loadFixture(deployOracleFixture);

			// Deploy price feed with zero price
			const MockAggregatorFactory = await hre.ethers.getContractFactory("MockAggregatorV3");
			const invalidPriceFeed = await MockAggregatorFactory.deploy(8, 0);

			await oracle.addPriceFeed(await usdc.getAddress(), await invalidPriceFeed.getAddress());

			const amount = hre.ethers.parseUnits("1000", 6);

			await expect(
				oracle.getUsdValue(await usdc.getAddress(), amount)
			).to.be.revertedWithCustomError(oracle, "InvalidPrice");
		});
	});

	describe("Get USD Value - PT Tokens", function () {
		async function setupPTTokenFixture() {
			const fixture = await deployOracleFixture();
			const { oracle, ptToken, usdc, usdcPriceFeed, mockPendleOracle } = fixture;

			// Setup USDC price feed
			await oracle.addPriceFeed(await usdc.getAddress(), await usdcPriceFeed.getAddress());

			const mockMarket = "0x1234567890123456789012345678901234567890";

			// Setup PT token (use asset rate)
			await oracle.addPTToken(
				await ptToken.getAddress(),
				mockMarket,
				false, // useSy = false
				await usdc.getAddress()
			);

			// Set PT to Asset rate in mock Pendle oracle (1 PT = 0.95 USDC)
			await mockPendleOracle.setPtToAssetRate(mockMarket, hre.ethers.parseEther("0.95"));

			return { ...fixture, mockMarket };
		}

		it("Should calculate USD value correctly for PT token using asset rate", async function () {
			const { oracle, ptToken } = await loadFixture(setupPTTokenFixture);

			const amount = hre.ethers.parseUnits("1000", 6); // 1000 PT tokens (6 decimals, matching USDC)
			const usdValue = await oracle.getUsdValue(await ptToken.getAddress(), amount);

			// Expected: 1000 PT * 0.95 (PT rate) = 950 USDC * $1.00 = $950.00
			expect(usdValue).to.equal(95000000000n); // $950 with 8 decimals
		});

		it("Should calculate USD value correctly for PT token using SY rate", async function () {
			const { oracle, usdc, usdcPriceFeed, mockPendleOracle } = await loadFixture(deployOracleFixture);

			// Deploy new PT token for SY test (must match USDC decimals = 6)
			const MockERC20Factory = await hre.ethers.getContractFactory("MockERC20");
			const ptTokenSy = await MockERC20Factory.deploy("PT Token SY", "PTSY", 6, hre.ethers.parseUnits("1000000", 6));

			await oracle.addPriceFeed(await usdc.getAddress(), await usdcPriceFeed.getAddress());

			const mockMarket = "0x2234567890123456789012345678901234567890";

			// Setup PT token (use SY rate)
			await oracle.addPTToken(
				await ptTokenSy.getAddress(),
				mockMarket,
				true, // useSy = true
				await usdc.getAddress()
			);

			// Set PT to SY rate (1 PT = 0.98 SY/USDC)
			await mockPendleOracle.setPtToSyRate(mockMarket, hre.ethers.parseEther("0.98"));

			const amount = hre.ethers.parseUnits("1000", 6); // 1000 PT tokens (6 decimals)
			const usdValue = await oracle.getUsdValue(await ptTokenSy.getAddress(), amount);

			// Expected: 1000 PT * 0.98 (SY rate) = 980 USDC * $1.00 = $980.00
			expect(usdValue).to.equal(98000000000n); // $980 with 8 decimals
		});

		it("Should handle PT token with different underlying price", async function () {
			const { oracle, ptToken, usdc } = await loadFixture(setupPTTokenFixture);

			// Update USDC price to $1.05
			const MockAggregatorFactory = await hre.ethers.getContractFactory("MockAggregatorV3");
			const newUsdcPriceFeed = await MockAggregatorFactory.deploy(8, 105000000);
			await oracle.addPriceFeed(await usdc.getAddress(), await newUsdcPriceFeed.getAddress());

			const amount = hre.ethers.parseUnits("1000", 6); // 1000 PT tokens (6 decimals)
			const usdValue = await oracle.getUsdValue(await ptToken.getAddress(), amount);

			// Expected: 1000 PT * 0.95 = 950 USDC * $1.05 = $997.50
			expect(usdValue).to.be.closeTo(99750000000n, 100000000n); // Allow small rounding error
		});
	});

	describe("Pendle Oracle Management", function () {
		it("Should allow owner to update Pendle oracle", async function () {
			const { oracle } = await loadFixture(deployOracleFixture);

			const newOracleAddress = "0x1111111111111111111111111111111111111111";

			await expect(
				oracle.setPendleOracle(newOracleAddress)
			).to.emit(oracle, "PendleOracleUpdated");

			expect(await oracle.pendleOracle()).to.equal(newOracleAddress);
		});

		it("Should not allow non-owner to update Pendle oracle", async function () {
			const { oracle, user1 } = await loadFixture(deployOracleFixture);

			const newOracleAddress = "0x1111111111111111111111111111111111111111";

			await expect(
				oracle.connect(user1).setPendleOracle(newOracleAddress)
			).to.be.revertedWithCustomError(oracle, "OwnableUnauthorizedAccount");
		});

		it("Should not allow zero address for Pendle oracle update", async function () {
			const { oracle } = await loadFixture(deployOracleFixture);

			await expect(
				oracle.setPendleOracle(hre.ethers.ZeroAddress)
			).to.be.revertedWithCustomError(oracle, "InvalidToken");
		});
	});

	describe("View Functions", function () {
		it("Should return correct price feed", async function () {
			const { oracle, usdc, usdcPriceFeed } = await loadFixture(deployOracleFixture);

			await oracle.addPriceFeed(await usdc.getAddress(), await usdcPriceFeed.getAddress());

			expect(await oracle.getPriceFeed(await usdc.getAddress())).to.equal(
				await usdcPriceFeed.getAddress()
			);
		});

		it("Should return zero address for non-existent price feed", async function () {
			const { oracle, usdc } = await loadFixture(deployOracleFixture);

			expect(await oracle.getPriceFeed(await usdc.getAddress())).to.equal(
				hre.ethers.ZeroAddress
			);
		});

		it("Should return correct PT market", async function () {
			const { oracle, ptToken, mockMarket } = await loadFixture(setupPTTokenFixture);

			expect(await oracle.getPTMarket(await ptToken.getAddress())).to.equal(mockMarket);
		});

		it("Should correctly identify PT tokens", async function () {
			const { oracle, ptToken, usdc } = await loadFixture(setupPTTokenFixture);

			expect(await oracle.isPTToken(await ptToken.getAddress())).to.be.true;
			expect(await oracle.isPTToken(await usdc.getAddress())).to.be.false;
		});
	});

	async function setupPTTokenFixture() {
		const fixture = await deployOracleFixture();
		const { oracle, ptToken, usdc, usdcPriceFeed, mockPendleOracle } = fixture;

		await oracle.addPriceFeed(await usdc.getAddress(), await usdcPriceFeed.getAddress());

		const mockMarket = "0x1234567890123456789012345678901234567890";

		await oracle.addPTToken(
			await ptToken.getAddress(),
			mockMarket,
			false,
			await usdc.getAddress()
		);

		await mockPendleOracle.setPtToAssetRate(mockMarket, hre.ethers.parseEther("0.95"));

		return { ...fixture, mockMarket };
	}
});
