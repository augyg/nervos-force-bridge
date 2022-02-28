{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE OverloadedStrings #-}

module Backend where

import Common.Route
import Obelisk.Backend

import System.Which
import System.Process
import System.Directory

import System.IO (print)
import Control.Monad.Log
import Control.Monad.IO.Class (liftIO, MonadIO)

import Cardano.Binary

import Prettyprinter (pretty)
import Data.Text as T

import CKB
import CKB.RPC

import ADA
import ADA.Contracts.Bridge
import Control.Concurrent


backend :: Backend BackendRoute FrontendRoute
backend = Backend
  { _backend_run = \serve -> do
      downloadConfigFiles "ada-config"
      --runDevelopmentChain "ckb"
      --forkIO $ do
        --threadDelay 1000000
        --testRPC

      -- ckbInitDev
      -- flip runLoggingT (print . renderWithSeverity id) $ do
      -- logMessage $ WithSeverity Informational (pretty gitPath)
      serve $ const $ return ()
  , _backend_routeEncoder = fullRouteEncoder
  }
