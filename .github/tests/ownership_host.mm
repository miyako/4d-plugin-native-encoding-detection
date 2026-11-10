#import <Carbon/Carbon.h>
#include "4DPlugin-Native-Encoding-Detection.h"
#include "PrivateTypes.h"
#include "EntryPoints.h"
#include "ARRAY_TEXT.h"
#include "C_TEXT.h"
#include <cstring>
#include <cstdlib>
#include <stdexcept>

static void check(bool condition, const char* message)
{
    if(!condition) {
        std::cerr << message << "\n";
        std::exit(1);
    }
}

static int deniedPlatform()
{
    check(false, "unexpected platform operation");
    return 0;
}

// Redirect before compiling the actual dispatcher, not after dispatch.
#define TECCountAvailableTextEncodings(count) (*(count) = 0, noErr)
#define TECGetAvailableTextEncodings(...) deniedPlatform()
#define TECCreateSniffer(...) deniedPlatform()
#define TECSniffTextEncoding(...) deniedPlatform()
#define TECDisposeSniffer(...) deniedPlatform()
#define GetScriptInfoFromTextEncoding(...) deniedPlatform()
#define CFStringGetNameOfEncoding(...) ((CFStringRef)(uintptr_t)deniedPlatform())
#define CFStringConvertEncodingToIANACharSetName(...) ((CFStringRef)(uintptr_t)deniedPlatform())
#define CFStringConvertEncodingToWindowsCodepage(...) deniedPlatform()
#include "4DPlugin-Native-Encoding-Detection.cpp"

struct Node {
    int refs = 1;
    std::map<CUTF16String, PA_Variable> properties;
    std::vector<PA_Variable> elements;
};

static std::map<PA_Unichar*, size_t> strings;
static std::map<PA_Handle, size_t> handles;
static std::map<PA_Picture, int> pictures;
static std::map<Node*, bool> nodes;
static bool nullEmpty;
static bool failProperty;
static bool failStringify;
static bool failStringifyHandle;
static bool failNextHandle;
static bool mismatchStringify;
static PA_long32 blobLength;
static CUTF16String fixture;

static PA_Unistring makeString(const PA_Unichar* text)
{
    size_t units = 0;
    while(text && text[units]) ++units;
    PA_Unistring value = {};
    if(units || !nullEmpty) {
        value.fString = new PA_Unichar[units + 1];
        if(units) std::memcpy(value.fString, text, units * sizeof(PA_Unichar));
        value.fString[units] = 0;
        value.fLength = static_cast<PA_long32>(units);
        strings[value.fString] = units;
    }
    return value;
}

static CUTF16String readString(PA_Unistring value)
{
    if(!value.fString) {
        check(value.fLength == 0, "null string has nonzero length");
        return {};
    }
    check(strings.count(value.fString), "read dead/unowned string");
    check(strings.at(value.fString) == static_cast<size_t>(value.fLength),
          "string length/capacity mismatch");
    check(value.fString[value.fLength] == 0, "missing terminator");
    return CUTF16String(value.fString, value.fLength);
}

static void disposeString(PA_Unistring value)
{
    readString(value);
    if(value.fString) {
        strings.erase(value.fString);
        delete[] value.fString;
    }
}

static Node* node(void* ref)
{
    auto n = static_cast<Node*>(ref);
    check(nodes.count(n), "dead object/collection reference");
    return n;
}

static Node* makeNode(bool collection)
{
    auto n = new Node;
    nodes[n] = collection;
    return n;
}

static void clear(PA_Variable*);

static void release(void* ref)
{
    if(!ref) return;
    auto n = node(ref);
    if(--n->refs == 0) {
        for(auto& p : n->properties) clear(&p.second);
        for(auto& v : n->elements) clear(&v);
        nodes.erase(n);
        delete n;
    }
}

static PA_Picture makePicture()
{
    PA_Picture p = new uint8_t(42);
    pictures[p] = 1;
    return p;
}

static PA_Variable copy(PA_Variable v)
{
    switch(v.fType) {
    case eVK_Unistring: {
        auto text = readString(v.uValue.fString);
        v.uValue.fString = makeString(text.c_str());
        break;
    }
    case eVK_Object:
        if(v.uValue.fObject) ++node(v.uValue.fObject)->refs;
        break;
    case eVK_Collection:
        if(v.uValue.fCollection) ++node(v.uValue.fCollection)->refs;
        break;
    case eVK_Picture:
        check(pictures.count(v.uValue.fPicture), "copy dead picture");
        ++pictures[v.uValue.fPicture];
        break;
    case eVK_Undefined: case eVK_Null: case eVK_Real:
    case eVK_Longint: case eVK_Boolean:
        break;
    default: check(false, "unexpected copied kind");
    }
    return v;
}

static void clear(PA_Variable* v)
{
    switch(v->fType) {
    case eVK_Unistring: disposeString(v->uValue.fString); break;
    case eVK_Object: release(v->uValue.fObject); break;
    case eVK_Collection: release(v->uValue.fCollection); break;
    case eVK_Picture: {
        auto p = v->uValue.fPicture;
        check(pictures.count(p), "release dead picture");
        if(--pictures[p] == 0) {
            pictures.erase(p);
            delete static_cast<uint8_t*>(p);
        }
        break;
    }
    case eVK_ArrayUnicode: {
        auto h = v->uValue.fArray.fData;
        check(handles.count(h), "clear dead array");
        auto data = reinterpret_cast<PA_Unistring*>(*h);
        check(handles[h] >= (v->uValue.fArray.fNbElements + 1) * sizeof(*data),
              "array count exceeds actual capacity");
        for(int i = 0; i <= v->uValue.fArray.fNbElements; ++i) disposeString(data[i]);
        std::free(*h);
        delete h;
        handles.erase(h);
        break;
    }
    case eVK_Undefined: case eVK_Null: case eVK_Real:
    case eVK_Longint: case eVK_Boolean:
        break;
    default: check(false, "cleared unspecified failure output");
    }
    v->fType = eVK_Undefined;
}

static void host(short selector, EngineBlock* eb)
{
    switch(selector) {
    case EX_GET_INFORMATION: eb->fParam2 = 0x00002000; break;
    case EX_CONVERT_STRING:
        check(eb->fParam1 == 4 && handles.count(eb->fHandle), "unexpected blob conversion");
        eb->fParam4 = blobLength;
        if(eb->fParam3) {
            check(blobLength == 1, "unexpected blob copy");
            *reinterpret_cast<uint8_t*>(eb->fParam3) = 42;
        }
        break;
    case EX_CREATE_UNISTRING:
        eb->fUniString1 = makeString(reinterpret_cast<PA_Unichar*>(eb->fHandle));
        break;
    case EX_DISPOSE_UNISTRING: disposeString(eb->fUniString1); break;
    case EX_SET_UNISTRING: {
        auto replacement = makeString(reinterpret_cast<PA_Unichar*>(eb->fHandle));
        disposeString(eb->fUniString1);
        eb->fUniString1 = replacement;
        break;
    }
    case EX_VARIABLE_TO_STRING: {
        auto v = reinterpret_cast<PA_Variable*>(eb->fHandle);
        check(v->fType == eVK_Unistring, "read unspecified/nonstring output");
        readString(v->uValue.fString);
        eb->fUniString1 = v->uValue.fString;
        break;
    }
    case EX_CLEAR_VARIABLE: clear(static_cast<PA_Variable*>(eb->fPtr1)); break;
    case EX_CREATE_PICTURE: eb->fPicture = makePicture(); break;
    case EX_DISPOSE_PICTURE: {
        PA_Variable v = {};
        PA_SetPictureVariable(&v, eb->fPicture);
        clear(&v);
        break;
    }
    case EX_HANDLE_MANAGER: {
        auto h = eb->fHandle;
        switch(eb->fParam1) {
        case 1:
            if(failNextHandle) {
                failNextHandle = false;
                eb->fHandle = nullptr;
                eb->fError = eER_IncompatibleTypes;
                break;
            }
            h = new char*;
            *h = static_cast<char*>(std::calloc(1, std::max<sLONG_PTR>(1, eb->fParam2)));
            check(*h, "fixture handle allocation failed");
            handles[h] = eb->fParam2;
            eb->fHandle = h;
            break;
        case 2:
            check(handles.count(h), "dispose dead handle");
            std::free(*h); delete h; handles.erase(h);
            break;
        case 3: {
            check(handles.count(h), "resize dead handle");
            auto data = static_cast<char*>(std::realloc(*h, std::max<sLONG_PTR>(1, eb->fParam2)));
            check(data, "fixture resize allocation failed");
            *h = data; handles[h] = eb->fParam2;
            break;
        }
        case 4: check(handles.count(h), "size dead handle"); eb->fParam2 = handles[h]; break;
        case 5:
            check(handles.count(h), "lock dead handle");
            eb->fParam3 = reinterpret_cast<sLONG_PTR>(*h);
            break;
        case 6: check(handles.count(h), "unlock dead handle"); break;
        default: check(false, "unexpected handle operation");
        }
        break;
    }
    case EX_GET_OBJ_VALUE: {
        auto n = node(eb->fPtr1);
        auto out = static_cast<PA_Variable*>(eb->fPtr2);
        if(failProperty) {
            std::memset(out, 0xa5, sizeof(*out));
            eb->fError = eER_IncompatibleTypes;
        } else if(eb->fShort == eVK_Collection) {
            PA_SetLongintVariable(out, static_cast<PA_long32>(n->elements.size()));
        } else {
            auto key = readString(eb->fUniString1);
            check(n->properties.count(key), "getter missing fixture property");
            *out = copy(n->properties.at(key));
        }
        break;
    }
    case EX_SET_OBJ_VALUE: {
        auto n = node(eb->fPtr1);
        auto incoming = copy(*static_cast<PA_Variable*>(eb->fPtr2));
        if(eb->fShort == eVK_Collection) {
            check(eb->fLongint == n->elements.size(), "unexpected collection index");
            n->elements.push_back(incoming);
        } else {
            auto key = readString(eb->fUniString1);
            auto previous = n->properties.find(key);
            if(previous != n->properties.end()) clear(&previous->second);
            n->properties[key] = incoming;
        }
        break;
    }
    case EX_EXECUTE_COMMAND_BY_ID: {
        auto args = static_cast<PA_Variable**>(eb->fPtr1);
        auto out = static_cast<PA_Variable*>(eb->fPtr2);
        check(out->fType == eVK_Undefined, "command result not initialized");
        switch(eb->fParam1) {
        case 1471: PA_SetObjectVariable(out, makeNode(false)); break;
        case 1472: PA_SetCollectionVariable(out, makeNode(true)); break;
        case 1231: {
            auto n = node(args[0]->uValue.fObject);
            PA_SetBooleanVariable(out, n->properties.count(readString(args[1]->uValue.fString)));
            break;
        }
        case 1225: {
            auto n = node(args[0]->uValue.fObject);
            auto duplicate = makeNode(false);
            for(auto& p : n->properties) duplicate->properties[p.first] = copy(p.second);
            PA_SetObjectVariable(out, duplicate);
            if(failStringifyHandle) failNextHandle = true;
            break;
        }
        case 1217:
            node(args[0]->uValue.fObject);
            if(failStringify) {
                std::memset(out, 0xa5, sizeof(*out));
                eb->fError = eER_IncompatibleTypes;
            } else if(mismatchStringify) {
                PA_SetCollectionVariable(out, makeNode(true));
            } else {
                auto text = makeString(fixture.c_str());
                PA_SetStringVariable(out, &text);
            }
            break;
        default: check(false, "unexpected command selector");
        }
        break;
    }
    default:
        std::cerr << "unexpected engine selector " << selector << "\n";
        std::exit(1);
    }
}

static CUTF16String utf16(const char* text)
{
    auto str = CFStringCreateWithCString(kCFAllocatorDefault, text, kCFStringEncodingUTF8);
    check(str, "invalid fixture UTF8");
    CUTF16String out(CFStringGetLength(str), 0);
    if(!out.empty()) CFStringGetCharacters(str, CFRangeMake(0, out.size()), &out[0]);
    CFRelease(str);
    return out;
}

static void scalarControl()
{
    auto input = PA_CreateUnistring(const_cast<PA_Unichar*>(fixture.c_str()));
    auto output = PA_CreateUnistring(nullptr);
    BytePtr args[] = {reinterpret_cast<BytePtr>(&input)};
    C_TEXT wrapper;
    wrapper.fromParamAtIndex(args, 1);
    auto changed = utf16("changed");
    PA_SetUnistring(&input, const_cast<PA_Unichar*>(changed.c_str()));
    args[0] = reinterpret_cast<BytePtr>(&output);
    wrapper.toParamAtIndex(args, 1);
    check(readString(output) == fixture, "borrowed scalar was not independently copied");
    auto returned = PA_CreateUnistring(nullptr);
    auto resultPtr = &returned;
    wrapper.setReturn(reinterpret_cast<sLONG_PTR*>(&resultPtr));
    check(readString(returned) == fixture, "wrapper scalar return content");
    PluginBlock block = {};
    block.fResult = &resultPtr;
    PA_ReturnString(&block, const_cast<PA_Unichar*>(fixture.c_str()));
    check(readString(returned) == fixture, "SDK scalar return content");
    PA_DisposeUnistring(&input);
    PA_DisposeUnistring(&output);
    PA_DisposeUnistring(&returned);
}

static void arrayControl()
{
    auto ar = PA_CreateVariable(eVK_ArrayUnicode);
    PA_ResizeArray(&ar, 2);
    for(int i = 0; i <= 2; ++i) {
        auto owned = PA_CreateUnistring(const_cast<PA_Unichar*>(fixture.c_str()));
        PA_SetStringInArray(ar, i, &owned);
    }
    ARRAY_TEXT wrapper;
    BytePtr args[] = {reinterpret_cast<BytePtr>(&ar)};
    wrapper.fromParamAtIndex(args, 1);
    auto changed = utf16("changed");
    auto replacement = PA_CreateUnistring(const_cast<PA_Unichar*>(changed.c_str()));
    PA_SetStringInArray(ar, 0, &replacement);
    wrapper.toParamAtIndex(args, 1);
    for(int i = 0; i <= 2; ++i)
        check(readString(PA_GetStringInArray(ar, i)) == fixture, "array copy/transfer content");
    if(!fixture.empty() || !nullEmpty)
        check(PA_GetStringInArray(ar, 0).fString != PA_GetStringInArray(ar, 1).fString,
              "array outputs share allocation");
    auto rejected = PA_CreateUnistring(const_cast<PA_Unichar*>(fixture.c_str()));
    PA_SetStringInArray(ar, -1, &rejected);
    PA_SetStringInArray(ar, 3, &rejected);
    auto wrong = PA_CreateVariable(eVK_Longint);
    PA_SetStringInArray(wrong, 0, &rejected);
    auto missing = ar;
    missing.uValue.fArray.fData = nullptr;
    PA_SetStringInArray(missing, 0, &rejected);
    PA_SetStringInArray(ar, 0, nullptr);
    check(readString(rejected) == fixture, "rejected transfer consumed owner");
    PA_DisposeUnistring(&rejected);
    wrapper.setSize(1);
    wrapper.toParamAtIndex(args, 1);
    wrapper.setSize(0);
    wrapper.toParamAtIndex(args, 1);
    PA_ClearVariable(&ar);
}

static void helperCase(const std::string& name, const char* text)
{
    auto obj = makeNode(false);
    auto key = utf16("key");
    if(name == "set-narrow") ob_set_s(obj, "key", text);
    else if(name == "set-wide") ob_set_s(obj, L"key", text);
    else if(name == "set-utf16") ob_set_a(obj, L"key", &fixture);
    else if(name == "set-wchar") {
        auto str = CFStringCreateWithCString(kCFAllocatorDefault, text, kCFStringEncodingUTF8);
        std::vector<wchar_t> wide(fixture.size() + 1, 0);
        CFIndex used = 0;
        CFStringGetBytes(str, CFRangeMake(0, CFStringGetLength(str)), kCFStringEncodingUTF32LE,
                         0, false, reinterpret_cast<UInt8*>(wide.data()),
                         (wide.size() - 1) * sizeof(wchar_t), &used);
        CFRelease(str);
        ob_set_a(obj, L"key", wide.data());
    } else if(name == "picture") ob_set_p(obj, L"key", makePicture());
    else if(name == "handoffs") {
        ob_set_o(obj, L"child", makeNode(false));
        ob_set_o(obj, "child2", makeNode(false));
        ob_set_c(obj, L"key", makeNode(true));
        auto c = ob_get_c(obj, L"key");
        check(c && node(c)->refs == 2, "collection getter must hand off owning reference");
        PA_DisposeCollection(c);
    } else if(name.find("get-") == 0) {
        PA_Variable v = PA_CreateVariable(eVK_Undefined);
        if(name == "get-text-collection" || name == "get-number-collection" ||
           name == "get-collection-failure")
            PA_SetCollectionVariable(&v, makeNode(true));
        else if(name.find("object") != std::string::npos)
            PA_SetObjectVariable(&v, makeNode(false));
        else if(name.find("picture") != std::string::npos)
            PA_SetPictureVariable(&v, makePicture());
        else if(name.find("bool-match") != std::string::npos)
            PA_SetBooleanVariable(&v, true);
        else if(name.find("number-match") != std::string::npos)
            PA_SetRealVariable(&v, 42);
        else {
            auto textValue = makeString(fixture.c_str());
            PA_SetStringVariable(&v, &textValue);
        }
        obj->properties[key] = v;
        failProperty = name.find("failure") != std::string::npos;
        bool threw = false;
        CUTF8String output(reinterpret_cast<const uint8_t*>("unchanged"));
        try {
            if(name.find("text") != std::string::npos) {
                check(ob_get_a(obj, L"key", &output), "existing property lost");
                if(name == "get-text")
                    check(output == CUTF8String(reinterpret_cast<const uint8_t*>(text)), "getter UTF8 bytes");
            } else if(name.find("bool") != std::string::npos) {
                bool result = ob_get_b(obj, L"key");
                if(name == "get-bool-match") check(result, "matching boolean");
            } else if(name.find("number") != std::string::npos) {
                double result = ob_get_n(obj, L"key");
                if(name == "get-number-match") check(result == 42, "matching real");
            } else {
                check(!ob_get_c(obj, L"key"), "mismatch returned collection");
            }
        } catch(const std::runtime_error&) { threw = true; }
        check(threw == failProperty, "property failure was not surfaced");
    } else if(name.find("stringify") == 0) {
        failStringify = name == "stringify-failure";
        failStringifyHandle = name == "stringify-handle-failure";
        mismatchStringify = name == "stringify-mismatch";
        CUTF8String output(reinterpret_cast<const uint8_t*>("unchanged"));
        bool threw = false;
        try { ob_stringify(obj, &output); }
        catch(const std::runtime_error&) { threw = true; }
        check(threw == (failStringify || failStringifyHandle || mismatchStringify),
              "stringify failure was not surfaced");
        if(threw)
            check(output == CUTF8String(reinterpret_cast<const uint8_t*>("unchanged")),
                  "failure overwritten with empty success");
        else check(output == CUTF8String(reinterpret_cast<const uint8_t*>(text)), "stringify exact UTF8");
    } else if(name == "missing") {
        CUTF8String output;
        check(!ob_get_a(obj, L"missing", &output), "missing text property");
        check(!ob_get_b(obj, L"missing"), "missing boolean property");
        check(ob_get_n(obj, L"missing") == 0, "missing real property");
        check(!ob_get_c(obj, L"missing"), "missing collection property");
    } else check(false, "unknown helper case");
    if(name.find("set-") == 0)
        check(readString(obj->properties.at(key).uValue.fString) == fixture, "setter exact UTF16 units");
    release(obj);
}

int main(int argc, char** argv)
{
    check(argc == 4, "case/text/empty-engine required");
    gCall4D = host;
    nullEmpty = std::string(argv[3]) == "null";
    fixture = utf16(argv[2]);
    std::string name = argv[1];
    if(name == "scalar") scalarControl();
    else if(name == "arrays") arrayControl();
    else if(name == "dispatcher") {
        PluginMain(kInitPlugin, nullptr);
        const PA_long32 lengths[] = {0, 1, 256L * 1024L * 1024L + 1};
        for(PA_long32 length : lengths) {
            blobLength = length;
            PA_Handle data = PA_NewHandle(length == 1 ? 1 : 0);
            PA_ObjectRef options = nullptr, result = nullptr;
            void* args[] = {&data, &options};
            PluginBlock block = {};
            block.fParameters = args;
            block.fResult = &result;
            PluginMain(1, &block);
            check(result, "dispatcher did not return object");
            auto n = node(result);
            check(n->properties.count(utf16("encodings")), "missing result collection");
            if(length > 256L * 1024L * 1024L)
                check(n->properties.count(utf16("error")), "oversize blob error lost");
            release(result);
            PA_DisposeHandle(data);
        }
    } else helperCase(name, argv[2]);
    check(strings.empty(), "unbalanced string allocations");
    check(pictures.empty(), "unbalanced picture references");
    check(nodes.empty(), "unbalanced object/collection references");
    check(handles.empty(), "unbalanced handles");
    std::cout << "PASS " << name << " strings=0 pictures=0 nodes=0 handles=0\n";
}
