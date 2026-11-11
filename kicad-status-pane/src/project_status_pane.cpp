/*
 * Project Status pane for the KiCad project manager.
 *
 * This program source code file is part of KiCad, a free EDA CAD application.
 */

#include "project_status_pane.h"

#include <kicad_manager_frame.h>
#include <file_history.h>

#include <wx/arrstr.h>
#include <wx/button.h>
#include <wx/dataview.h>
#include <wx/datetime.h>
#include <wx/dir.h>
#include <wx/file.h>
#include <wx/filename.h>
#include <wx/ffile.h>
#include <wx/memory.h>
#include <wx/sizer.h>
#include <wx/stattext.h>
#include <wx/textfile.h>
#include <wx/utils.h>
#include <wx/wfstream.h>
#include <wx/zipstrm.h>

#include <utility>
#include <vector>


namespace
{

wxString CacheFileFor( const wxString& aProjectFile )
{
    wxFileName fn( aProjectFile );
    return fn.GetPath() + wxFILE_SEP_PATH + ".kicad_status_cache.txt";
}


int CountOccurrences( const wxString& aText, const wxString& aNeedle )
{
    int      count = 0;
    wxString rest  = aText;
    size_t   pos;

    while( ( pos = rest.find( aNeedle ) ) != wxString::npos )
    {
        ++count;
        rest = rest.Mid( pos + aNeedle.length() );
    }

    return count;
}


// Recursively collects all files below a root directory.
class ZIP_COLLECTOR : public wxDirTraverser
{
public:
    explicit ZIP_COLLECTOR( const wxString& aRoot ) : m_root( aRoot ) {}

    wxDirTraverseResult OnFile( const wxString& aPath ) override
    {
        wxString rel = aPath;

        if( rel.StartsWith( m_root, &rel ) && rel.StartsWith( wxFILE_SEP_PATH ) )
            rel.Remove( 0, 1 );

        m_files.emplace_back( rel, aPath );

        return wxDIR_CONTINUE;
    }

    wxDirTraverseResult OnDir( const wxString& WXUNUSED( aDir ) ) override
    {
        return wxDIR_CONTINUE;
    }

    wxString                                   m_root;
    std::vector<std::pair<wxString, wxString>> m_files;    // (archive name, full path)
};

} // namespace


PROJECT_STATUS_PANE::PROJECT_STATUS_PANE( KICAD_MANAGER_FRAME* aParent ) :
        wxPanel( aParent, wxID_ANY, wxDefaultPosition, wxDefaultSize, wxTAB_TRAVERSAL ),
        m_frame( aParent )
{
    wxBoxSizer* top = new wxBoxSizer( wxVERTICAL );

    m_list = new wxDataViewListCtrl( this, wxID_ANY, wxDefaultPosition, wxDefaultSize,
                                     wxDV_SINGLE | wxDV_ROW_LINES );
    m_list->AppendTextColumn( _( "Project" ), wxDATAVIEW_CELL_INERT, FromDIP( 150 ) );
    m_list->AppendTextColumn( _( "Path" ),    wxDATAVIEW_CELL_INERT, FromDIP( 240 ) );
    m_list->AppendTextColumn( _( "DRC" ),     wxDATAVIEW_CELL_INERT, FromDIP( 80 ) );
    m_list->AppendTextColumn( _( "ERC" ),     wxDATAVIEW_CELL_INERT, FromDIP( 80 ) );
    top->Add( m_list, 1, wxEXPAND | wxALL, FromDIP( 4 ) );

    auto* buttons = new wxFlexGridSizer( 2, 4, FromDIP( 4 ), FromDIP( 4 ) );
    buttons->AddGrowableCol( 0, 1 );
    buttons->AddGrowableCol( 1, 1 );
    buttons->AddGrowableCol( 2, 1 );
    buttons->AddGrowableCol( 3, 1 );

    m_btnOpen    = new wxButton( this, wxID_ANY, _( "Open" ) );
    m_btnFolder  = new wxButton( this, wxID_ANY, _( "Folder" ) );
    m_btnBackup  = new wxButton( this, wxID_ANY, _( "Backup" ) );
    m_btnExport  = new wxButton( this, wxID_ANY, _( "Export" ) );
    m_btnDrc     = new wxButton( this, wxID_ANY, _( "DRC" ) );
    m_btnErc     = new wxButton( this, wxID_ANY, _( "ERC" ) );
    m_btnRefresh = new wxButton( this, wxID_ANY, _( "Refresh" ) );

    buttons->Add( m_btnOpen,    0, wxEXPAND );
    buttons->Add( m_btnFolder,  0, wxEXPAND );
    buttons->Add( m_btnBackup,  0, wxEXPAND );
    buttons->Add( m_btnExport,  0, wxEXPAND );
    buttons->Add( m_btnDrc,     0, wxEXPAND );
    buttons->Add( m_btnErc,     0, wxEXPAND );
    buttons->Add( m_btnRefresh, 0, wxEXPAND );
    buttons->AddStretchSpacer();

    top->Add( buttons, 0, wxEXPAND | wxALL, FromDIP( 4 ) );

    m_status = new wxStaticText( this, wxID_ANY, wxEmptyString );
    top->Add( m_status, 0, wxEXPAND | wxLEFT | wxRIGHT | wxBOTTOM, FromDIP( 4 ) );

    SetSizer( top );

    m_btnOpen->Bind( wxEVT_BUTTON, &PROJECT_STATUS_PANE::OnOpen, this );
    m_btnFolder->Bind( wxEVT_BUTTON, &PROJECT_STATUS_PANE::OnFolder, this );
    m_btnBackup->Bind( wxEVT_BUTTON, &PROJECT_STATUS_PANE::OnBackup, this );
    m_btnDrc->Bind( wxEVT_BUTTON, &PROJECT_STATUS_PANE::OnDrc, this );
    m_btnErc->Bind( wxEVT_BUTTON, &PROJECT_STATUS_PANE::OnErc, this );
    m_btnExport->Bind( wxEVT_BUTTON, &PROJECT_STATUS_PANE::OnExport, this );
    m_btnRefresh->Bind( wxEVT_BUTTON, &PROJECT_STATUS_PANE::OnRefresh, this );

    RefreshProjectList();
}


void PROJECT_STATUS_PANE::RefreshProjectList()
{
    m_list->DeleteAllItems();
    m_projects.clear();

    FILE_HISTORY& history = m_frame->GetFileHistory();

    for( size_t i = 0; i < history.GetCount(); ++i )
    {
        wxString path = history.GetHistoryFile( i );

        if( path.empty() || !wxFileName::FileExists( path ) )
            continue;

        wxFileName fn( path );
        wxString   drc = ReadCache( path, "drc" );
        wxString   erc = ReadCache( path, "erc" );

        wxVector<wxVariant> values;
        values.push_back( wxVariant( fn.GetName() ) );
        values.push_back( wxVariant( fn.GetPath() ) );
        values.push_back( wxVariant( drc.empty() ? wxString( "-" ) : drc ) );
        values.push_back( wxVariant( erc.empty() ? wxString( "-" ) : erc ) );

        m_list->AppendItem( values );
        m_projects.push_back( path );
    }
}


wxString PROJECT_STATUS_PANE::GetSelectedProjectFile() const
{
    wxDataViewItem item = m_list->GetSelection();
    long           row  = m_list->ItemToRow( item );

    if( row < 0 || static_cast<size_t>( row ) >= m_projects.size() )
        return wxEmptyString;

    return m_projects[static_cast<size_t>( row )];
}


wxString PROJECT_STATUS_PANE::ReadCache( const wxString& aProjectFile, const wxString& aKey ) const
{
    wxString file = CacheFileFor( aProjectFile );

    if( !wxFileExists( file ) )
        return wxEmptyString;

    wxTextFile t;
    t.Open( file );

    if( !t.IsOpened() )
        return wxEmptyString;

    wxString prefix = aKey + "=";

    for( size_t i = 0; i < t.GetLineCount(); ++i )
    {
        wxString line = t.GetLine( i );

        if( line.StartsWith( prefix ) )
            return line.Mid( prefix.length() );
    }

    return wxEmptyString;
}


void PROJECT_STATUS_PANE::WriteCache( const wxString& aProjectFile, const wxString& aKey,
                                      const wxString& aValue ) const
{
    wxString file = CacheFileFor( aProjectFile );

    // read existing lines (wxTextFile has no SetLine/filename-Write in wx 3.2)
    wxArrayString lines;

    if( wxFileExists( file ) )
    {
        wxTextFile t;

        if( t.Open( file ) && t.IsOpened() )
        {
            for( size_t i = 0; i < t.GetLineCount(); ++i )
                lines.Add( t.GetLine( i ) );
        }
    }

    wxString prefix = aKey + "=";
    bool     found  = false;

    for( size_t i = 0; i < lines.size(); ++i )
    {
        if( lines[i].StartsWith( prefix ) )
        {
            lines[i] = prefix + aValue;
            found      = true;
            break;
        }
    }

    if( !found )
        lines.Add( prefix + aValue );

    wxFFile f( file, "w" );

    if( !f.IsOpened() )
        return;

    for( const auto& l : lines )
        f.Write( l + "\n" );

    f.Close();
}


void PROJECT_STATUS_PANE::RunCheck( const wxString& aProjectFile, bool aDrc )
{
    wxFileName fn( aProjectFile );
    wxString   base   = fn.GetPath() + wxFILE_SEP_PATH + fn.GetName();
    wxString   target = aDrc ? base + ".kicad_pcb" : base + ".kicad_sch";

    if( !wxFileExists( target ) )
    {
        m_status->SetLabel( wxString::Format( _( "No %s file found for project %s." ),
                                              aDrc ? _( "PCB" ) : _( "schematic" ), fn.GetName() ) );
        return;
    }

    wxString cmd = wxString::Format( "kicad-cli %s %s --format json --exit-code-violations \"%s\"",
                                     aDrc ? "pcb" : "sch", aDrc ? "drc" : "erc", target );

    m_status->SetLabel( wxString::Format( _( "Running %s for %s ..." ),
                                          aDrc ? "DRC" : "ERC", fn.GetName() ) );
    wxSafeYield();

    wxArrayString out, err;
    wxExecute( cmd, out, err, wxEXEC_SYNC );

    wxString text;

    for( const auto& l : out )
        text += l + "\n";

    for( const auto& l : err )
        text += l + "\n";

    int errors   = CountOccurrences( text, "\"severity\": \"error\"" )
                 + CountOccurrences( text, "\"severity\":\"error\"" );
    int warnings = CountOccurrences( text, "\"severity\": \"warning\"" )
                 + CountOccurrences( text, "\"severity\":\"warning\"" );

    wxString summary = wxString::Format( "%dE/%dW", errors, warnings );
    WriteCache( aProjectFile, aDrc ? "drc" : "erc", summary );

    m_status->SetLabel( wxString::Format( _( "%s %s: %s (errors/warnings)" ),
                                          aDrc ? "DRC" : "ERC", fn.GetName(), summary ) );

    RefreshProjectList();
}


void PROJECT_STATUS_PANE::DoBackup( const wxString& aProjectFile )
{
    wxFileName fn( aProjectFile );
    wxString   dir  = fn.GetPath();
    wxString   stamp = wxDateTime::Now().Format( "%Y%m%d_%H%M%S" );
    wxString   zipPath = dir + wxFILE_SEP_PATH + fn.GetName() + "_backup_" + stamp + ".zip";

    {
        wxFileOutputStream out( zipPath );

        if( !out.IsOk() )
        {
            m_status->SetLabel( wxString::Format( _( "Cannot write backup file %s" ), zipPath ) );
            return;
        }

        wxZipOutputStream zip( out );
        ZIP_COLLECTOR     trav( dir );

        wxDir( dir ).Traverse( trav );

        for( const auto& [arc, full] : trav.m_files )
        {
            if( full == zipPath )
                continue;

            wxFile f( full, wxFile::read );

            if( !f.IsOpened() )
                continue;

            zip.PutNextEntry( arc );

            char   buf[65536];
            size_t n;

            while( ( n = f.Read( buf, sizeof( buf ) ) ) > 0 )
                zip.Write( buf, n );
        }

        zip.Close();
    }

    m_status->SetLabel( wxString::Format( _( "Backup written: %s" ), zipPath ) );
}


void PROJECT_STATUS_PANE::DoExport( const wxString& aProjectFile )
{
    wxFileName fn( aProjectFile );
    wxString   dir  = fn.GetPath();
    wxString   base = dir + wxFILE_SEP_PATH + fn.GetName();
    wxString   prod = dir + wxFILE_SEP_PATH + "production";

    wxFileName::Mkdir( prod, wxS_DIR_DEFAULT, wxPATH_MKDIR_FULL );

    wxString pcb = base + ".kicad_pcb";
    wxString sch = base + ".kicad_sch";

    wxArrayString cmds;

    if( wxFileExists( pcb ) )
    {
        cmds.push_back( wxString::Format( "kicad-cli pcb export gerbers --output \"%s\" \"%s\"", prod, pcb ) );
        cmds.push_back( wxString::Format( "kicad-cli pcb export drill --format excellon --output \"%s\" \"%s\"", prod, pcb ) );
    }

    if( wxFileExists( sch ) )
        cmds.push_back( wxString::Format( "kicad-cli sch export pdf --output \"%s\" \"%s\"", prod, sch ) );

    if( cmds.empty() )
    {
        m_status->SetLabel( _( "No .kicad_pcb or .kicad_sch found, nothing to export." ) );
        return;
    }

    for( const auto& c : cmds )
    {
        wxArrayString out, err;
        wxExecute( c, out, err, wxEXEC_SYNC );
    }

    m_status->SetLabel( wxString::Format( _( "Exported to %s" ), prod ) );
}


void PROJECT_STATUS_PANE::OnOpen( wxCommandEvent& WXUNUSED( aEvent ) )
{
    wxString p = GetSelectedProjectFile();

    if( !p.empty() )
        m_frame->LoadProject( wxFileName( p ) );
}


void PROJECT_STATUS_PANE::OnFolder( wxCommandEvent& WXUNUSED( aEvent ) )
{
    wxString p = GetSelectedProjectFile();

    if( !p.empty() )
        wxLaunchDefaultApplication( wxFileName( p ).GetPath() );
}


void PROJECT_STATUS_PANE::OnBackup( wxCommandEvent& WXUNUSED( aEvent ) )
{
    wxString p = GetSelectedProjectFile();

    if( !p.empty() )
        DoBackup( p );
}


void PROJECT_STATUS_PANE::OnDrc( wxCommandEvent& WXUNUSED( aEvent ) )
{
    wxString p = GetSelectedProjectFile();

    if( !p.empty() )
        RunCheck( p, true );
}


void PROJECT_STATUS_PANE::OnErc( wxCommandEvent& WXUNUSED( aEvent ) )
{
    wxString p = GetSelectedProjectFile();

    if( !p.empty() )
        RunCheck( p, false );
}


void PROJECT_STATUS_PANE::OnExport( wxCommandEvent& WXUNUSED( aEvent ) )
{
    wxString p = GetSelectedProjectFile();

    if( !p.empty() )
        DoExport( p );
}


void PROJECT_STATUS_PANE::OnRefresh( wxCommandEvent& WXUNUSED( aEvent ) )
{
    RefreshProjectList();
    m_status->SetLabel( wxEmptyString );
}
