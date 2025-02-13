{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TemplateHaskell #-}

-- | 

module Bridge.Cardano.Types where

import Common.Bridge 
import Common.Cardano
import Common.Nervos

import GHC.Generics
import Data.Traversable
import Text.Read (readMaybe)
import Data.Map (Map)
import qualified Data.Map as Map

import qualified Data.Text as T
import Data.Aeson
import Data.Aeson.TH

import Bridge.Utils
import qualified Bridge.Nervos.Types as CKB

-- TODO(skylar): This is a testnet address
newtype Address =
  Address { unAddress :: T.Text }
  deriving (Eq, Show)

-- newtype TxHash =
--   TxHash { unTxHash :: T.Text }
--   deriving (Eq, Show)

-- TODO(skylar): Steal this from cardano
data AssetType
  = Ada
  | AssetName T.Text
  deriving (Eq, Show, Read, Ord, Generic)

data TxOutput = TxOutput
  { txOutput_address :: T.Text
  , txOutput_amount :: Map AssetType Integer
  }
  deriving (Eq, Show, Generic)

data LockTx =
  LockTx { lockTxHash :: AdaTxHash
         , lockTxLockScript :: Script -- CKB.Script previously
         , lockTxLovelace :: Integer
         }
  deriving (Eq, Show)

data LockMetadata = LockMetadata
  { mintToAddress :: T.Text
  }
  deriving (Eq, Show)

instance FromJSON AdaTxHash where
  parseJSON = withObject "TxHash" $ \o ->
    AdaTxHash <$> o .: "tx_hash"

instance ToJSON AdaTxHash where
  toJSON (AdaTxHash h) = object [ "tx_hash" .= h
                             ]

deriveJSON defaultOptions ''LockTx
deriveJSON defaultOptions ''AssetType
deriveJSON defaultOptions ''LockMetadata
instance ToJSONKey AssetType

instance FromJSON TxOutput where
  parseJSON = withObject "TxOutput" $ \v -> do
    address <- v .: "address"
    lv <- v .: "amount"
    values <- fmap mconcat <$> for lv $ \e -> do
      assetType <- assetTypeFromText <$> (e .: "unit")
      mQuantity <- readMaybe <$> e .: "quantity"
      case mQuantity of
        Nothing -> fail "Not a valid integer"
        Just quantity -> do
          pure $ Map.singleton assetType quantity
    pure $ TxOutput address values

instance ToJSON TxOutput

assetTypeFromText :: T.Text -> AssetType
assetTypeFromText "lovelace" = Ada
assetTypeFromText n = AssetName n
