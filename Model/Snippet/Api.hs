{-# LANGUAGE OverloadedStrings, DeriveGeneric #-}
module Model.Snippet.Api (
    addUser,
    setUserToken,
    getSnippet,
    addSnippet,
    updateSnippet,
    deleteSnippet,
    listSnippets,
    listSnippetsByLanguage,
    listSnippetsByOwner,
    listSnippetsByOwnerByLanguage
) where

import Import.NoFoundation hiding (id, toLower)
import Util.Api (createUser, updateUser)
import Util.Http (Links(..), httpPost, httpPut, httpGet, httpGetLink, httpDelete)
import Settings.Environment (snippetsApiBaseUrl, snippetsApiAdminToken)
import Data.Aeson (decode)
import Data.Maybe (fromJust)
import Data.Text (toLower)
import qualified Data.ByteString.Lazy as L
import Network.URI (parseURI, uriQuery)

data InternalSnippet = InternalSnippet {
    id :: Text,
    language :: Text,
    title :: Text,
    public :: Bool,
    owner :: Text,
    files_hash :: Text,
    modified :: Text,
    created :: Text,
    files :: Maybe [InternalSnippetFile]
} deriving (Show, Generic)

instance FromJSON InternalSnippet
instance ToJSON InternalSnippet

data InternalSnippetFile = InternalSnippetFile {
    name :: Text,
    content :: Text
} deriving (Show, Generic)

instance FromJSON InternalSnippetFile
instance ToJSON InternalSnippetFile

toSnippet :: InternalSnippet -> Snippet
toSnippet s =
    Snippet{
        snippetId=id s,
        snippetLanguage=language s,
        snippetTitle=title s,
        snippetPublic=public s,
        snippetOwner=owner s,
        snippetFilesHash=files_hash s,
        snippetModified=modified s,
        snippetCreated=created s,
        snippetFiles=map toSnippetFile $ fromJust $ files s
    }

toMetaSnippet :: InternalSnippet -> MetaSnippet
toMetaSnippet s =
    MetaSnippet{
        metaSnippetId=id s,
        metaSnippetLanguage=language s,
        metaSnippetTitle=title s,
        metaSnippetPublic=public s,
        metaSnippetOwner=owner s,
        metaSnippetModified=modified s,
        metaSnippetCreated=created s
    }

toSnippetFile :: InternalSnippetFile -> SnippetFile
toSnippetFile f =
    SnippetFile{
        snippetFileName=name f,
        snippetFileContent=content f
    }

linksToPagination :: Links -> Pagination
linksToPagination links =
    Pagination{
        paginationNextPage=parseQsPage $ relNext links,
        paginationPrevPage=parseQsPage $ relPrev links,
        paginationFirstPage=parseQsPage $ relFirst links,
        paginationLastPage=parseQsPage $ relLast links
    }

parseQsPage :: Maybe Text -> Maybe Text
parseQsPage (Just url) = join $ lookupQsParam "page" <$> qs
    where qs = parseSimpleQuery . encodeUtf8 . pack . uriQuery <$> uri
          uri = parseURI $ unpack url
parseQsPage Nothing = Nothing

lookupQsParam :: Text -> SimpleQuery -> Maybe Text
lookupQsParam _ [] = Nothing
lookupQsParam param ((key, value):xs)
    | param == decodeUtf8 key = Just $ decodeUtf8 value
    | otherwise = lookupQsParam param xs

addUser :: Text -> IO Text
addUser userToken = do
    url <- createUserUrl <$> snippetsApiBaseUrl
    adminToken <- snippetsApiAdminToken
    createUser url adminToken userToken

setUserToken :: Text -> Text -> IO ()
setUserToken userId userToken = do
    url <- (updateUserUrl userId) <$> snippetsApiBaseUrl
    adminToken <- snippetsApiAdminToken
    updateUser url adminToken userToken

addSnippet :: L.ByteString -> Maybe Text -> IO Snippet
addSnippet payload authToken = do
    apiUrl <- createSnippetUrl <$> snippetsApiBaseUrl
    body <- httpPost apiUrl authToken payload
    let mJson = decode body :: Maybe InternalSnippet
    return $ toSnippet $ fromJust mJson

updateSnippet :: Text -> L.ByteString -> Maybe Text -> IO Snippet
updateSnippet snippetId payload authToken = do
    apiUrl <- (snippetUrl snippetId) <$> snippetsApiBaseUrl
    body <- httpPut apiUrl authToken payload
    let mJson = decode body :: Maybe InternalSnippet
    return $ toSnippet $ fromJust mJson

getSnippet :: Text -> Maybe Text -> IO Snippet
getSnippet snippetId authToken = do
    apiUrl <- (snippetUrl snippetId) <$> snippetsApiBaseUrl
    body <- httpGet apiUrl authToken
    let mJson = decode body :: Maybe InternalSnippet
    return $ toSnippet $ fromJust mJson

deleteSnippet :: Text -> Maybe Text -> IO Bool
deleteSnippet snippetId authToken = do
    apiUrl <- (snippetUrl snippetId) <$> snippetsApiBaseUrl
    responseCode <- httpDelete apiUrl authToken
    return $ responseCode == 204

listSnippets :: Int -> Maybe Text -> IO ([MetaSnippet], Pagination)
listSnippets page authToken = do
    apiUrl <- (snippetsUrl page False) <$> snippetsApiBaseUrl
    (body, links) <- httpGetLink apiUrl authToken
    let mJson = decode body :: Maybe [InternalSnippet]
    return $ (map toMetaSnippet $ fromJust mJson, linksToPagination links)

listSnippetsByLanguage :: Text -> Int -> Maybe Text -> IO ([MetaSnippet], Pagination)
listSnippetsByLanguage lang page authToken = do
    apiUrl <- (snippetsByLanguageUrl lang page False) <$> snippetsApiBaseUrl
    (body, links) <- httpGetLink apiUrl authToken
    let mJson = decode body :: Maybe [InternalSnippet]
    return $ (map toMetaSnippet $ fromJust mJson, linksToPagination links)

listSnippetsByOwner :: Text -> Int -> Maybe Text -> IO ([MetaSnippet], Pagination)
listSnippetsByOwner userId page authToken = do
    apiUrl <- (snippetsByOwnerUrl userId page False) <$> snippetsApiBaseUrl
    (body, links) <- httpGetLink apiUrl authToken
    let mJson = decode body :: Maybe [InternalSnippet]
    return $ (map toMetaSnippet $ fromJust mJson, linksToPagination links)

listSnippetsByOwnerByLanguage :: Text -> Text -> Int -> Maybe Text -> IO ([MetaSnippet], Pagination)
listSnippetsByOwnerByLanguage userId lang page authToken = do
    apiUrl <- (snippetsByOwnerByLanguageUrl userId lang page False) <$> snippetsApiBaseUrl
    (body, links) <- httpGetLink apiUrl authToken
    let mJson = decode body :: Maybe [InternalSnippet]
    return $ (map toMetaSnippet $ fromJust mJson, linksToPagination links)

createSnippetUrl :: String -> String
createSnippetUrl baseUrl = baseUrl ++ "/snippets"

snippetUrl :: Text -> String -> String
snippetUrl snippetId baseUrl = baseUrl ++ "/snippets/" ++ unpack snippetId

snippetsUrl :: Int -> Bool -> String -> String
snippetsUrl page inclUntitled baseUrl =
    baseUrl ++ "/snippets" ++ "?page=" ++ show page  ++ "&per_page=20&include_untitled=" ++ boolToStr inclUntitled

createUserUrl :: String -> String
createUserUrl baseUrl = baseUrl ++ "/admin/users"

updateUserUrl :: Text -> String -> String
updateUserUrl userId baseUrl = baseUrl ++ "/admin/users/" ++ unpack userId

snippetsByOwnerUrl :: Text -> Int -> Bool -> String -> String
snippetsByOwnerUrl userId page inclUntitled baseUrl =
    snippetsUrl page inclUntitled baseUrl ++ "&owner=" ++ unpack userId

snippetsByOwnerByLanguageUrl :: Text -> Text -> Int -> Bool -> String -> String
snippetsByOwnerByLanguageUrl userId lang page inclUntitled baseUrl =
    snippetsUrl page inclUntitled baseUrl ++ "&owner=" ++ unpack userId ++ "&language=" ++ unpack lang

snippetsByLanguageUrl :: Text -> Int -> Bool -> String -> String
snippetsByLanguageUrl lang page inclUntitled baseUrl =
    snippetsUrl page inclUntitled baseUrl ++ "&language=" ++ unpack lang

boolToStr :: Bool -> String
boolToStr b = unpack . toLower . pack $ show b
