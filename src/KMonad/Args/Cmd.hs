{-|
Module      : KMonad.Args.Cmd
Description : Parse command-line options into a 'Cmd' for KMonad to execute
Copyright   : (c) David Janssen, 2019
License     : MIT

Maintainer  : janssen.dhj@gmail.com
Stability   : experimental
Portability : non-portable (MPTC with FD, FFI to Linux-only c-code)

-}
module KMonad.Args.Cmd
  ( Cmd(..)
  , HasCmd(..)
  , getCmd
  )
where

import KMonad.Prelude hiding (try)
import KMonad.Args.TH (gitHash)
import KMonad.Args.Types (DefSetting(..))
import KMonad.Util
import Paths_kmonad (version)

import qualified KMonad.Args.Parser as P
import qualified KMonad.Parsing as M  -- [M]egaparsec functionality

import Data.Version (showVersion)
import Options.Applicative


--------------------------------------------------------------------------------
-- $cmd
--
-- The different things KMonad can be instructed to do.

-- | Record describing the instruction to KMonad
data Cmd = Cmd
  { _cfgFile   :: FilePath     -- ^ Which file to read the config from
  , _dryRun    :: Bool         -- ^ Flag to indicate we are only test-parsing
  , _logLvl    :: LogLevel     -- ^ Level of logging to use
  , _strtDel   :: Milliseconds -- ^ How long to wait before acquiring the input keyboard

    -- All 'KDefCfg' options of a 'KExpr'
  , _cmdAllow  :: DefSetting       -- ^ Allow execution of arbitrary shell-commands?
  , _fallThrgh :: DefSetting       -- ^ Re-emit unhandled events?
  , _cmpSeq    :: Maybe DefSetting -- ^ Key to use for compose-key sequences
  , _cmpSeqDelay :: Maybe DefSetting -- ^ Specify compose sequence key delays
  , _keySeqDelay :: Maybe DefSetting -- ^ Specify key event output delays
  , _implArnd  :: Maybe DefSetting -- ^ How to handle implicit `around`s
  , _oToken    :: Maybe DefSetting -- ^ How to emit the output
  , _iToken    :: Maybe DefSetting -- ^ How to capture the input
  }
  deriving Show
makeClassy ''Cmd

-- | Parse 'Cmd' from the evocation of this program
getCmd :: IO Cmd
getCmd = customExecParser (prefs showHelpOnEmpty) $
  info (cmdP <**> versioner <**> helper)
    (  fullDesc
    <> progDesc "Start KMonad"
    <> header   "kmonad - an onion of buttons."
    )

-- | Equip a parser with version information about the program
versioner :: Parser (a -> a)
versioner = infoOption (showVersion version <> ", commit " <> fromMaybe "?" $(gitHash))
  (  long "version"
  <> short 'V'
  <> help "Show version"
  )

--------------------------------------------------------------------------------
-- $prs
--
-- The different command-line parsers

-- | Parse the full command
cmdP :: Parser Cmd
cmdP =
  Cmd <$> fileP
      <*> dryrunP
      <*> levelP
      <*> startDelayP
      <*> cmdAllowP
      <*> fallThrghP
      <*> cmpSeqP
      <*> cmpSeqDelayP
      <*> keySeqDelayP
      <*> implArndP
      <*> oTokenP
      <*> iTokenP

-- | Parse a filename that points us at the config-file
fileP :: Parser FilePath
fileP = strArgument
  (  metavar "FILE"
  <> help    "The configuration file")

-- | Parse a flag that allows us to switch to parse-only mode
dryrunP :: Parser Bool
dryrunP = switch
  (  long    "dry-run"
  <> short   'd'
  <> help    "If used, do not start KMonad, only try parsing the config file"
  )


-- | Parse the log-level as either a level option or a verbose flag
levelP :: Parser LogLevel
levelP = option f
  (  long    "log-level"
  <> short   'l'
  <> metavar "Log level"
  <> value   LevelWarn
  <> help    "How much info to print out (debug, info, warn, error)" )
  where
    f = maybeReader $ flip lookup [ ("debug", LevelDebug), ("warn", LevelWarn)
                                  , ("info",  LevelInfo),  ("error", LevelError) ]

-- | Allow the execution of arbitrary shell-commands
cmdAllowP :: Parser DefSetting
cmdAllowP = SAllowCmd <$> switch
  (  long "allow-cmd"
  <> short 'c'
  <> help "Whether to allow the execution of arbitrary shell-commands"
  )

-- | Re-emit unhandled events
fallThrghP :: Parser DefSetting
fallThrghP = SFallThrough <$> switch
  (  long "fallthrough"
  <> short 'f'
  <> help "Whether to simply re-emit unhandled events"
  )

-- | Key to use for compose-key sequences
cmpSeqP :: Parser (Maybe DefSetting)
cmpSeqP = optional $ SCmpSeq <$> option (megaReadM $ P.buttonP' True)
  (  long "cmp-seq"
  <> short 's'
  <> metavar "BUTTON"
  <> help "Which key to use to emit compose-key sequences"
  )

-- | Specify compose sequence key delays.
cmpSeqDelayP :: Parser (Maybe DefSetting)
cmpSeqDelayP = optional $ SCmpSeqDelay <$> option (megaReadM P.numP)
  (  long  "cmp-seq-delay"
  <> metavar "TIME"
  <> help  "How many ms to wait between each key of a compose sequence"
  )

-- | Specify key event output delays.
keySeqDelayP :: Parser (Maybe DefSetting)
keySeqDelayP = optional $ SKeySeqDelay <$> option (megaReadM P.numP)
  (  long  "key-seq-delay"
  <> metavar "TIME"
  <> help  "How many ms to wait between each key event outputted"
  )

-- | How to handle implicit `around`s
implArndP :: Parser (Maybe DefSetting)
implArndP = optional $ SImplArnd <$> option (megaReadM P.implArndP)
  (  long "implicit-around"
  <> long "ia"
  <> metavar "AROUND"
  <> help "How to translate implicit arounds (`A`, `S-a`)"
  )

-- | Where to emit the output
oTokenP :: Parser (Maybe DefSetting)
oTokenP = optional $ SOToken <$> option (mkTokenP P.otokens)
  (  long "output"
  <> short 'o'
  <> metavar "OTOKEN"
  <> help "Emit output to OTOKEN"
  )

-- | How to capture the keyboard input
iTokenP :: Parser (Maybe DefSetting)
iTokenP = optional $ SIToken <$> option (mkTokenP P.itokens)
  (  long "input"
  <> short 'i'
  <> metavar "ITOKEN"
  <> help "Capture input via ITOKEN"
  )

-- | Parse a flag that disables auto-releasing the release of enter
startDelayP :: Parser Milliseconds
startDelayP = option (fromIntegral <$> megaReadM P.numP)
  (  long  "start-delay"
  <> short 'w'
  <> value 300
  <> metavar "TIME"
  <> showDefaultWith (show . unMS )
  <> help  "How many ms to wait before grabbing the input keyboard (time to release enter if launching from terminal)")

-- | Transform a bunch of tokens of the form @(Keyword, Parser)@ into an
-- optparse-applicative parser
mkTokenP :: [(Text, M.Parser a)] -> ReadM a
mkTokenP = megaReadM . P.mkTokenP' True

-- | Megaparsec <--> optparse-applicative interface
megaReadM :: M.Parser a -> ReadM a
megaReadM p = eitherReader (mapLeft show . M.parse p "" . fromString)
