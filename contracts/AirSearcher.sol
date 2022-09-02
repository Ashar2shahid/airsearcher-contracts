// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;
import "@api3/airnode-protocol-v1/contracts/dapis/interfaces/IDapiServer.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./utils/ExtendedMulticall.sol";

/// @title Contract that serves Searchers to update the DapiServer datafeeds
/// with signed data
/// @notice A Searcher can update the beacon (i.e a single source datafeed)
/// using signed data that it won from the AirSearcher auction. Searchers can
/// also update multiple beacons simultaneously to update a beacon set i.e
/// a multisource aggregated datafeed.
/// @dev The AirSearcher contract acts as a proxy between the searchers contract and
/// the DapiServer, only searchers with the correct signatures can interact
/// with the proxy and subsequently update the DapiServer

contract AirSearcher is ExtendedMulticall {
    using ECDSA for bytes32;

    /// @notice Address of the DapiServer
    address public dapiServer;

    constructor(address _dapiServer) {
        require(_dapiServer != address(0), "dAPI server address zero");
        dapiServer = _dapiServer;
    }

    function getArraySum(uint256[] memory _array)
        public
        pure
        returns (uint256 sum_)
    {
        sum_ = 0;
        for (uint256 i = 0; i < _array.length; i++) {
            sum_ += _array[i];
        }
    }

    // @notice Registers the Beacon update subscription
    /// @dev A convience function to quickly register subscriptions
    /// that specify Airsearcher as the relayer
    /// @param airnode Airnode address
    /// @param templateId Template ID
    /// @return subscriptionId Subscription ID
    function registerSearcherBeaconUpdateSubscription(
        address airnode,
        bytes32 templateId
    ) external returns (bytes32 subscriptionId) {
        subscriptionId = IDapiServer(dapiServer)
            .registerBeaconUpdateSubscription(
                airnode,
                templateId,
                "0x",
                address(this),
                address(this)
            );
    }

    function fulfillSearcherPspBeaconUpdate(
        bytes32 subscriptionId,
        bytes32 beaconId,
        address airnode,
        uint256 bidAmount,
        uint256 timestamp,
        uint256 expireTimestamp,
        bytes calldata data,
        bytes calldata dapiSignature,
        bytes calldata searcherSignature
    ) external payable {
        require(
            beaconId ==
                IDapiServer(dapiServer).subscriptionIdToBeaconId(
                    subscriptionId
                ),
            "Subscription not registered"
        );
        require(
            (
                keccak256(
                    abi.encodePacked(
                        beaconId,
                        expireTimestamp,
                        msg.sender,
                        bidAmount
                    )
                ).toEthSignedMessageHash()
            ).recover(searcherSignature) == airnode,
            "Signature Mismatch"
        );
        require(block.timestamp < expireTimestamp, "Signature has expired");
        require(msg.value >= bidAmount, "Insufficient Bid amount");
        IDapiServer(dapiServer).fulfillPspBeaconUpdate(
            subscriptionId,
            airnode,
            address(this),
            address(this),
            timestamp,
            data,
            dapiSignature
        );
    }

    function fulfillSearcherPspBeaconSetUpdate(
        bytes32[] memory subscriptionIds,
        bytes32[] memory beaconIds,
        address[] memory airnodes,
        uint256[] memory bidAmounts,
        uint256[] memory timestamps,
        uint256[] memory expireTimestamps,
        bytes[] memory data,
        bytes[] memory dapiSignatures,
        bytes[] memory searcherSignatures
    ) external payable {
        uint256 beaconCount = airnodes.length;
        require(
            beaconCount == subscriptionIds.length &&
                beaconCount == beaconIds.length &&
                beaconCount == bidAmounts.length &&
                beaconCount == timestamps.length &&
                beaconCount == expireTimestamps.length &&
                beaconCount == data.length &&
                beaconCount == dapiSignatures.length &&
                beaconCount == searcherSignatures.length,
            "Parameter length mismatch"
        );
        require(beaconCount > 1, "Specified less than two Beacons");
        for (uint256 ind = 0; ind < beaconCount; ind++) {
            if (dapiSignatures[ind].length != 0) {
                require(
                    beaconIds[ind] ==
                        IDapiServer(dapiServer).subscriptionIdToBeaconId(
                            subscriptionIds[ind]
                        ),
                    "Subscription not registered"
                );
                require(
                    (
                        keccak256(
                            abi.encodePacked(
                                beaconIds[ind],
                                expireTimestamps[ind],
                                msg.sender,
                                bidAmounts[ind]
                            )
                        ).toEthSignedMessageHash()
                    ).recover(searcherSignatures[ind]) == airnodes[ind],
                    "Signature Mismatch"
                );
                require(
                    block.timestamp < expireTimestamps[ind],
                    "Signature has expired"
                );
                IDapiServer(dapiServer).fulfillPspBeaconUpdate(
                    subscriptionIds[ind],
                    airnodes[ind],
                    address(this),
                    address(this),
                    timestamps[ind],
                    data[ind],
                    dapiSignatures[ind]
                );
            }
        }
        uint256 totalBid = getArraySum(bidAmounts);
        require(msg.value >= totalBid, "Insufficient Bid amount");
        IDapiServer(dapiServer).updateBeaconSetWithBeacons(beaconIds);
    }
}
