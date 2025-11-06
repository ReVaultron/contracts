// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title VolatilityIndex
 * @dev Contract to track and store volatility data for token pairs using Pyth price feeds on Hedera
 * @notice Optimized for Hedera's low-cost transactions and integrates with Pyth oracle
 */
contract VolatilityIndex is Ownable, ReentrancyGuard {
    IPyth public pyth;

    struct VolatilityData {
        uint256 volatilityBps; // Volatility in basis points (5000 = 50%)
        int64 price; // Current price at time of calculation (Pyth format)
        uint64 confidence; // Pyth confidence interval
        int32 expo; // Price exponent from Pyth
        uint256 timestamp; // When this volatility was calculated
    }

    // Mapping from price feed ID to volatility data
    mapping(bytes32 => VolatilityData) public volatilityData;

    // Array of supported price feed IDs
    bytes32[] public supportedFeeds;

    // Mapping to check if a feed is supported
    mapping(bytes32 => bool) public isFeedSupported;

    // Mapping to track authorized updaters (can be agent contracts)
    mapping(address => bool) public isAuthorizedUpdater;

    // Maximum allowed volatility (10000% = 1,000,000 bps) - safety check
    uint256 public constant MAX_VOLATILITY_BPS = 1_000_000;

    // Maximum price staleness (in seconds) - reject prices older than this
    uint256 public maxPriceStaleness = 300; // 5 minutes

    // Events
    event VolatilityUpdated(
        bytes32 indexed priceFeedId,
        uint256 volatilityBps,
        int64 price,
        uint64 confidence,
        int32 expo,
        uint256 timestamp
    );
    event FeedAdded(bytes32 indexed priceFeedId, uint256 timestamp);
    event FeedRemoved(bytes32 indexed priceFeedId, uint256 timestamp);
    event UpdaterAuthorized(address indexed updater, uint256 timestamp);
    event UpdaterRevoked(address indexed updater, uint256 timestamp);
    event PriceStalenessUpdated(
        uint256 oldValue,
        uint256 newValue,
        uint256 timestamp
    );
    event PythContractUpdated(
        address oldPyth,
        address newPyth,
        uint256 timestamp
    );

    /**
     * @dev Constructor sets the Pyth contract address
     * @param pythContract The address of the Pyth price feeds contract on Hedera
     */
    constructor(address pythContract) Ownable(msg.sender) {
        require(
            pythContract != address(0),
            "VolatilityIndex: Invalid Pyth contract address"
        );
        pyth = IPyth(pythContract);

        // Owner is automatically authorized updater
        isAuthorizedUpdater[msg.sender] = true;
    }

    /**
     * @dev Updates volatility data for a specific price feed
     * @param priceUpdate The encoded price update data from Pyth Hermes
     * @param priceFeedId The price feed ID to update
     * @param volatilityBps The calculated volatility in basis points
     */
    function updateVolatility(
        bytes[] calldata priceUpdate,
        bytes32 priceFeedId,
        uint256 volatilityBps
    ) external payable nonReentrant {
        require(
            isAuthorizedUpdater[msg.sender],
            "VolatilityIndex: Unauthorized updater"
        );
        require(priceUpdate.length > 0, "VolatilityIndex: Empty price update");
        require(
            volatilityBps <= MAX_VOLATILITY_BPS,
            "VolatilityIndex: Invalid volatility"
        );

        // Get and pay the required fee for updating Pyth prices
        uint fee = pyth.getUpdateFee(priceUpdate);
        require(msg.value >= fee, "VolatilityIndex: Insufficient fee");

        // Update Pyth price feeds on-chain
        pyth.updatePriceFeeds{value: fee}(priceUpdate);

        // Get the current price from Pyth (with staleness check)
        PythStructs.Price memory price = pyth.getPriceNoOlderThan(
            priceFeedId,
            maxPriceStaleness
        );

        // Store volatility data
        volatilityData[priceFeedId] = VolatilityData({
            volatilityBps: volatilityBps,
            price: price.price,
            confidence: price.conf,
            expo: price.expo,
            timestamp: block.timestamp
        });

        // Add to supported feeds if not already added
        if (!isFeedSupported[priceFeedId]) {
            supportedFeeds.push(priceFeedId);
            isFeedSupported[priceFeedId] = true;
            emit FeedAdded(priceFeedId, block.timestamp);
        }

        emit VolatilityUpdated(
            priceFeedId,
            volatilityBps,
            price.price,
            price.conf,
            price.expo,
            block.timestamp
        );

        // Refund excess fee (important on Hedera to return unused tinybars)
        if (msg.value > fee) {
            (bool success, ) = payable(msg.sender).call{value: msg.value - fee}(
                ""
            );
            require(success, "VolatilityIndex: Refund failed");
        }
    }

    /**
     * @dev Batch update volatility for multiple price feeds
     * @param priceUpdate The encoded price update data from Pyth Hermes (contains multiple feeds)
     * @param priceFeedIds Array of price feed IDs to update
     * @param volatilitiesBps Array of calculated volatilities in basis points
     */
    function updateVolatilityBatch(
        bytes[] calldata priceUpdate,
        bytes32[] calldata priceFeedIds,
        uint256[] calldata volatilitiesBps
    ) external payable nonReentrant {
        require(
            isAuthorizedUpdater[msg.sender],
            "VolatilityIndex: Unauthorized updater"
        );
        require(priceUpdate.length > 0, "VolatilityIndex: Empty price update");
        require(
            priceFeedIds.length == volatilitiesBps.length,
            "VolatilityIndex: Array length mismatch"
        );
        require(priceFeedIds.length > 0, "VolatilityIndex: Empty arrays");

        // Get and pay the required fee for updating Pyth prices
        uint fee = pyth.getUpdateFee(priceUpdate);
        require(msg.value >= fee, "VolatilityIndex: Insufficient fee");

        // Update Pyth price feeds on-chain (single call for all feeds)
        pyth.updatePriceFeeds{value: fee}(priceUpdate);

        // Update each feed's volatility data
        for (uint256 i = 0; i < priceFeedIds.length; i++) {
            bytes32 priceFeedId = priceFeedIds[i];
            uint256 volatilityBps = volatilitiesBps[i];

            require(
                volatilityBps <= MAX_VOLATILITY_BPS,
                "VolatilityIndex: Invalid volatility"
            );

            // Get the current price from Pyth
            PythStructs.Price memory price = pyth.getPriceNoOlderThan(
                priceFeedId,
                maxPriceStaleness
            );

            // Store volatility data
            volatilityData[priceFeedId] = VolatilityData({
                volatilityBps: volatilityBps,
                price: price.price,
                confidence: price.conf,
                expo: price.expo,
                timestamp: block.timestamp
            });

            // Add to supported feeds if not already added
            if (!isFeedSupported[priceFeedId]) {
                supportedFeeds.push(priceFeedId);
                isFeedSupported[priceFeedId] = true;
                emit FeedAdded(priceFeedId, block.timestamp);
            }

            emit VolatilityUpdated(
                priceFeedId,
                volatilityBps,
                price.price,
                price.conf,
                price.expo,
                block.timestamp
            );
        }

        // Refund excess fee
        if (msg.value > fee) {
            (bool success, ) = payable(msg.sender).call{value: msg.value - fee}(
                ""
            );
            require(success, "VolatilityIndex: Refund failed");
        }
    }

    /**
     * @dev Gets the current volatility data for a price feed
     * @param priceFeedId The price feed ID
     * @return data The volatility data struct
     */
    function getVolatilityData(
        bytes32 priceFeedId
    ) external view returns (VolatilityData memory data) {
        return volatilityData[priceFeedId];
    }

    /**
     * @dev Gets the current volatility in basis points
     * @param priceFeedId The price feed ID
     * @return volatilityBps The volatility in basis points
     */
    function getVolatility(
        bytes32 priceFeedId
    ) external view returns (uint256 volatilityBps) {
        return volatilityData[priceFeedId].volatilityBps;
    }

    /**
     * @dev Gets the current price for a price feed with full precision
     * @param priceFeedId The price feed ID
     * @return price The current price (raw Pyth format)
     * @return expo The price exponent
     * @return confidence The confidence interval
     */
    function getCurrentPrice(
        bytes32 priceFeedId
    ) external view returns (int64 price, int32 expo, uint64 confidence) {
        VolatilityData memory data = volatilityData[priceFeedId];
        return (data.price, data.expo, data.confidence);
    }

    /**
     * @dev Gets the normalized price (price * 10^18 / 10^expo)
     * @param priceFeedId The price feed ID
     * @return normalizedPrice The normalized price with 18 decimals
     */
    function getNormalizedPrice(
        bytes32 priceFeedId
    ) external view returns (uint256 normalizedPrice) {
        VolatilityData memory data = volatilityData[priceFeedId];

        // Convert to uint256 and normalize to 18 decimals
        if (data.price < 0) return 0; // Negative prices shouldn't happen

        uint256 price = uint256(int256(data.price));
        int32 expo = data.expo;

        if (expo >= 0) {
            // Price is in format: price * 10^expo
            normalizedPrice = price * (10 ** uint32(expo)) * 1e18;
        } else {
            // Price is in format: price / 10^(-expo)
            // Normalize to 18 decimals: price * 10^18 / 10^(-expo)
            uint32 absExpo = uint32(-expo);
            if (absExpo <= 18) {
                normalizedPrice = price * (10 ** (18 - absExpo));
            } else {
                normalizedPrice = price / (10 ** (absExpo - 18));
            }
        }

        return normalizedPrice;
    }

    /**
     * @dev Gets the last update timestamp for a price feed
     * @param priceFeedId The price feed ID
     * @return timestamp The last update timestamp
     */
    function getLastUpdate(
        bytes32 priceFeedId
    ) external view returns (uint256 timestamp) {
        return volatilityData[priceFeedId].timestamp;
    }

    /**
     * @dev Checks if volatility data is stale
     * @param priceFeedId The price feed ID
     * @param stalenessThreshold Maximum age in seconds
     * @return isStale True if data is older than threshold
     */
    function isVolatilityStale(
        bytes32 priceFeedId,
        uint256 stalenessThreshold
    ) external view returns (bool isStale) {
        uint256 lastUpdate = volatilityData[priceFeedId].timestamp;
        if (lastUpdate == 0) return true; // Never updated
        return (block.timestamp - lastUpdate) > stalenessThreshold;
    }

    /**
     * @dev Gets all supported price feed IDs
     * @return feeds Array of supported price feed IDs
     */
    function getSupportedFeeds()
        external
        view
        returns (bytes32[] memory feeds)
    {
        return supportedFeeds;
    }

    /**
     * @dev Gets the number of supported feeds
     * @return count The number of supported feeds
     */
    function getSupportedFeedCount() external view returns (uint256 count) {
        return supportedFeeds.length;
    }

    /**
     * @dev Checks if a price feed is supported
     * @param priceFeedId The price feed ID
     * @return supported True if the feed is supported
     */
    function isSupported(
        bytes32 priceFeedId
    ) external view returns (bool supported) {
        return isFeedSupported[priceFeedId];
    }

    /**
     * @dev Authorizes an address to update volatility (only owner)
     * @param updater The address to authorize
     */
    function authorizeUpdater(address updater) external onlyOwner {
        require(
            updater != address(0),
            "VolatilityIndex: Invalid updater address"
        );
        require(
            !isAuthorizedUpdater[updater],
            "VolatilityIndex: Already authorized"
        );

        isAuthorizedUpdater[updater] = true;
        emit UpdaterAuthorized(updater, block.timestamp);
    }

    /**
     * @dev Revokes authorization for an address (only owner)
     * @param updater The address to revoke
     */
    function revokeUpdater(address updater) external onlyOwner {
        require(
            isAuthorizedUpdater[updater],
            "VolatilityIndex: Not authorized"
        );
        require(updater != owner(), "VolatilityIndex: Cannot revoke owner");

        isAuthorizedUpdater[updater] = false;
        emit UpdaterRevoked(updater, block.timestamp);
    }

    /**
     * @dev Updates the maximum price staleness (only owner)
     * @param newStaleness New staleness threshold in seconds
     */
    function setMaxPriceStaleness(uint256 newStaleness) external onlyOwner {
        require(newStaleness > 0, "VolatilityIndex: Invalid staleness");
        require(newStaleness <= 3600, "VolatilityIndex: Staleness too high"); // Max 1 hour

        uint256 oldValue = maxPriceStaleness;
        maxPriceStaleness = newStaleness;

        emit PriceStalenessUpdated(oldValue, newStaleness, block.timestamp);
    }

    /**
     * @dev Updates the Pyth contract address (only owner, emergency use)
     * @param newPyth The new Pyth contract address
     */
    function updatePythContract(address newPyth) external onlyOwner {
        require(newPyth != address(0), "VolatilityIndex: Invalid Pyth address");

        address oldPyth = address(pyth);
        pyth = IPyth(newPyth);

        emit PythContractUpdated(oldPyth, newPyth, block.timestamp);
    }

    /**
     * @dev Removes a price feed from supported feeds (only owner)
     * @param priceFeedId The price feed ID to remove
     */
    function removeFeed(bytes32 priceFeedId) external onlyOwner {
        require(
            isFeedSupported[priceFeedId],
            "VolatilityIndex: Feed not supported"
        );

        // Remove from supported feeds array
        for (uint256 i = 0; i < supportedFeeds.length; i++) {
            if (supportedFeeds[i] == priceFeedId) {
                supportedFeeds[i] = supportedFeeds[supportedFeeds.length - 1];
                supportedFeeds.pop();
                break;
            }
        }

        isFeedSupported[priceFeedId] = false;
        emit FeedRemoved(priceFeedId, block.timestamp);
    }

    /**
     * @dev Withdraws HBAR from the contract (only owner)
     * @param to Address to send HBAR to
     */
    function withdrawHBAR(address payable to) external onlyOwner nonReentrant {
        require(to != address(0), "VolatilityIndex: Invalid recipient");

        uint256 balance = address(this).balance;
        require(balance > 0, "VolatilityIndex: No HBAR to withdraw");

        (bool success, ) = to.call{value: balance}("");
        require(success, "VolatilityIndex: Withdrawal failed");
    }

    /**
     * @dev Gets the contract's HBAR balance
     * @return balance The balance in tinybars
     */
    function getHBARBalance() external view returns (uint256 balance) {
        return address(this).balance;
    }

    /**
     * @dev Allows the contract to receive HBAR
     */
    receive() external payable {
        // Contract can receive HBAR for Pyth fees
    }
}
