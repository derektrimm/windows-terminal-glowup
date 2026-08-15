@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # install.ps1 / uninstall.ps1 are interactive console programs; colored
        # Write-Host status lines are their user interface, not log output.
        'PSAvoidUsingWriteHost'
        # oh-my-posh init and zoxide init are the vendors' documented setup
        # lines; both emit shell code that must be evaluated.
        'PSAvoidUsingInvokeExpression'
        # The profile publishes $global:ProjectRoots so users can override it
        # from the prompt; that reach is the point.
        'PSAvoidGlobalVars'
        # Settings, Defaults, and Keybindings are the domain nouns of
        # settings.json; singularizing them would misname what they hold.
        'PSUseSingularNouns'
        # Register-ArgumentCompleter fixes the completer scriptblock's
        # signature; the leading parameters are required but unused.
        'PSReviewUnusedParameter'
    )
}
