{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE DataKinds #-}

-- | 

module Bridge where

import Control.Monad
import Control.Monad.IO.Class
import Control.Concurrent (threadDelay)
import Network.Web3.Provider (Provider)
import qualified Data.Text as T
import Data.Maybe
import qualified Data.Map as M

import Data.Aeson
import Data.Aeson.TH

import Servant
import Servant.Client (ClientM, client, ClientEnv, parseBaseUrl, mkClientEnv, runClientM, Scheme(Https)
                      , BaseUrl(BaseUrl), ClientError)
import Network.HTTP.Client (Manager, newManager)
import Network.HTTP.Client.TLS (tlsManagerSettings)

import Network.Wai.Handler.Warp (run)

import Bridge.Utils

import qualified Bridge.Nervos.Types as CKB
import qualified Bridge.Nervos as CKB

import qualified Bridge.Cardano.Blockfrost as BF
-- TODO Unify these
import qualified Bridge.Cardano.Types as Ada
import qualified Bridge.Cardano as Ada

import Bridge.Nervos.Cli

{-
We need to load the provider
We need to load the contract location
We need to load the listen address
We need to load the multisig address that we will listen on

Multisig Addresss
We will do 3 verifiers with 2 things

collector
ckt1qyq8d80l0z2y40hwkjjhkc68yv48gau2dwlsvzucru

verifiers
ckt1qyqvsv5240xeh85wvnau2eky8pwrhh4jr8ts8vyj37
ckt1qyqywrwdchjyqeysjegpzw38fvandtktdhrs0zaxl4
tx build-multisig-address --sighash-address ckt1qyqvsv5240xeh85wvnau2eky8pwrhh4jr8ts8vyj37 ckt1qyqywrwdchjyqeysjegpzw38fvandtktdhrs0zaxl4  --threshold 1

ckt1qyq8d80l0z2y40hwkjjhkc68yv48gau2dwlsvzucru
ckt1qyqvsv5240xeh85wvnau2eky8pwrhh4jr8ts8vyj37

Here is the multisig info for the current verifiers

lock-arg: 0x901d84b53c1e05fc89a54f5c50346ae267f43aab
lock-hash: 0xe12969536f7c5e0c689af22bd63addafb45da4e1ea6031f317ab34ffc98c53f1
mainnet: ckb1qyqeq8vyk57pup0u3xj57hzsx34wyel5824slztglf
testnet: ckt1qyqeq8vyk57pup0u3xj57hzsx34wyel5824sz84hn4

The deployed contract is code-hash is:
0x82a4784a46f42916f144bfd1926fda614560e403bc131408881de82fee0724ad

The outpoint (where the contract was deployed):
0xb8e114fe03ca612c2987f56d6126c87a3aad3647156dbb8b2a16fc9888676776
0x0

Funds have to be transferred to the multisig address at this time
-}

data VerifierConfig =
  VerifierConfig { verifierConfigNode :: Provider
                 , verifierConfigIndexer :: Provider

                 , verifierNervosMultisigAddress :: CKB.Address

                 , verifierNervosPersonalAddress :: CKB.Address
                 , verifierNervosPassword :: T.Text

                 , verifierNervosDeployedScript :: CKB.DeployedScript
                 , verifierCardanoAddress :: Ada.Address

                 , verifierApiKey :: BF.ApiKey
                 -- TODO(galen): does a verifier need to know its own port?
                 , verifierConfigPort :: Int
                 }
  deriving (Eq)

data CollectorConfig =
  CollectorConfig { collectorConfigNode :: Provider
                  , collectorConfigIndexer :: Provider
                  
                  , collectorNervosMultisigAddress :: CKB.Address
                  , collectorNervosDeployedScript :: CKB.DeployedScript

                  , collectorCardanoAddress :: Ada.Address

                  , collectorApiKey :: BF.ApiKey

                  , collectorMultiSigConfig :: MultiSigConfigs
                  , collectorVerifierUrls :: [String]
                 }
  deriving (Eq)

data Response =
  Response { responseSignature :: Maybe Signature }
  deriving (Eq, Show)

data Request =
  Request { requestLock :: Ada.LockTx }
  deriving (Eq, Show)

deriveJSON defaultOptions ''Request
deriveJSON defaultOptions ''Response

type VerifierAPI =
 "sign" :> ReqBody '[JSON] Request :> Get '[JSON] Response

verifierApiProxy :: Proxy VerifierAPI
verifierApiProxy = Proxy

verifierServer :: VerifierConfig -> Server VerifierAPI
verifierServer = handleSignatureRequest

verifierApplication :: VerifierConfig -> Application
verifierApplication vc = serve verifierApiProxy $ verifierServer vc

runVerifierServer :: MonadIO m => VerifierConfig -> m ()
runVerifierServer vc = liftIO $ run (verifierConfigPort vc) (verifierApplication vc)

requestSignature :: Request -> ClientM (Response)
requestSignature = client verifierApiProxy

-- TODO(galen): properly set ports 
handleSignatureRequest :: VerifierConfig -> Request -> Servant.Handler Response
handleSignatureRequest vc (Request lockTx) =
  liftIO $ runBridge $ do
    locks <- Ada.getLockTxsAt apiKey $ verifierCardanoAddress vc
    mints <- CKB.getMintTxsAt ckb indexer $ CKB.deployedScriptScript deployedScript
    let
      foundLock = isJust $ headMay $ filter (== lockTx) $ getUnmintedLocks locks mints

    Response <$> case foundLock of
      False -> pure Nothing
      True -> do
        txFile <- buildMintTxn multiSigAddress deployedScript lockTx
        signTxFile txFile sigAddress pass
        txn <- liftIO $ decodeFileStrict txFile
        case getFirstSignature txn of 
          Just sig -> pure sig
          Nothing -> pure Nothing


        -- TODO(skylar): Extend the Signature/MultiSig Configs and signTxFile functions to get back the signature
        -- return it here

  where
    getFirstSignature (TxFile _ _ (Signatures map)) = headMay . snd =<< headMay $ toList map 
    deployedScript = verifierNervosDeployedScript vc
    multiSigAddress = verifierNervosMultisigAddress vc
    sigAddress = verifierNervosPersonalAddress vc
    pass = verifierNervosPassword vc

    ckb = verifierConfigNode vc
    indexer = verifierConfigIndexer vc

    apiKey = verifierApiKey vc

headMay :: [a] -> Maybe a
headMay (x:_) = Just x
headMay _ = Nothing


-- Hardcoded to use https for better security 
-- TODO(galen): Change this to configure to each URL for verifiers 
myMkClientEnv :: Int -> Manager -> String -> ClientEnv 
myMkClientEnv port manager domain = mkClientEnv manager (BaseUrl Http domain port "")

getValidMintTxs :: [(Ada.LockTx, [Either ClientError (Maybe Signature)])] -> [(Ada.LockTx, [Signature])] 
getValidMintTxs txnsResponses = filter signaturesAtLeast2
                                $ fmap (\(tx, emSigs) -> (tx, catMaybes $ fmap (join . eitherToMaybe) emSigs)) 
                                $ txnsResponses
  where
    signaturesAtLeast2 :: 

eitherToMaybe :: Either e a -> Maybe a
eitherToMaybe (Right a) = Just a
eitherToMaybe (Left _) = Nothing 

runCollector :: BridgeM m => CollectorConfig -> m ()
runCollector vc = forever $ do
  locks <- Ada.getLockTxsAt apiKey $ collectorCardanoAddress vc
  mints <- CKB.getMintTxsAt ckb indexer $ CKB.deployedScriptScript deployedScript

  manager <- liftIO $ newManager tlsManagerSettings
  let unMinted = getUnmintedLocks locks mints

      requestsToMint :: [Request] 
      requestsToMint = Request <$> unMinted 

      -- TODO(galen): code this to zip with the 5 ports for starting the verifiers 
      clientEnvs = [ myMkClientEnv 8000 manager "localhost"
                   , myMkClientEnv 8001 manager "localhost"
                   , myMkClientEnv 8002 manager "localhost"
                   ] 
        
      requestSignatures :: [Request] -> ClientM [Response]
      requestSignatures reqs = mapM requestSignature reqs 

      getResponses :: [Request] -> ClientEnv -> IO [Response]
      getResponses reqs clientEnv = runClientM (requestSignatures reqs) clientEnv 

      -- requestVerifiersSignatures
      verifyTransaction :: [ClientEnv] -> Request -> IO [Either ClientError Response]
      verifyTransaction envs req = mapM (runClientM $ requestSignature req) envs

  -- represents list of lists_A where lists_A is a Maybe Signature; the inner list thererfore
  -- represents whether the transaction should succeed 
  possibleMints <- mapM (verifyTransaction clientEnvs) requestsToMint

  let
    -- TODO(galen): should we make this a set?
    reqRes :: [(Ada.LockTx, [Either ClientError Signature])]
    reqRes = zip unMinted (fmap catMaybes $ (fmap.fmap) responseSignature possibleMints)

    getValid :: [(Ada.LockTx, [Either ClientError Signature])] -> [(Ada.LockTx, [Signature])] 
    getValid = filter shouldMint 

  
  mintFilePaths <- mapM (buildMintTxn multiSigAddress deployedScript) $ fmap fst $ shouldMint reqRes

  -- TODO(galen): make it very clear that the Ada.LockTx -> TxFile =is= ckb_mint 
  let
    toSign :: [(FilePath, [Signature])] 
    toSign = zip mintFilePaths $ snd <$> (shouldMint reqRes)
    
    addSigsToTxFile :: BridgeM m => [Signature] -> FilePath -> m () 
    addSigsToTxFile signatures path = do
      Just txn <- liftIO $ decodeFileStrict path
      liftIO $ encodeFile path
        $ TxFile txn multiSigConfig
        $ Signatures $ M.fromList [((fst . head . M.toList $ multiSigMap), signatures)]


  mapM (\(fp, sigs) -> addSigsToTxFile sigs fp) toSign
  mapM submitTxFromFile mintFilePaths 
 
  -- TODO(skylar): For each verifier call the requestSignature client function above, providing the endpoint
  -- this will give you the list of signatures you need

  liftIO $ threadDelay 1000000
  pure ()
  where
    multiSigAddress = collectorNervosMultisigAddress vc
    multiSigConfig = collectorMultiSigConfig vc
    MultiSigConfigs multiSigMap = multiSigConfig 
    deployedScript = collectorNervosDeployedScript vc
    ckb = collectorConfigNode vc
    indexer = collectorConfigIndexer vc
    verifierUrls = collectorVerifierUrls vc 
    apiKey = collectorApiKey vc

{-
buildMintTx :: BridgeM m => Ada.LockTx -> m ()
buildMintTx (Ada.LockTx _ _ _) = do
  pure ()
-}
getUnmintedLocks :: [Ada.LockTx] -> [CKB.MintTx] -> [Ada.LockTx]
getUnmintedLocks ls ms =
  filter (\lt -> not $ any (comp lt) ms) ls
  where
    comp (Ada.LockTx _ lscr v) (CKB.MintTx mscr v') = lscr == mscr && v == v'
