# gitolite #

This gem is designed to provide a Ruby interface to the [gitolite](https://github.com/sitaramc/gitolite) git backend system.  I am aiming to provide all management functionality that is available via the gitolite-admin repository (like SSH keys, repository permissions, etc)

This gem can still have problems.  Please file an issue if you encounter a bug.  If you have a feature request, file one please.

## Features ##
* Allows for the creation and management of repos within gitolite
* Allows for the creation and deletion of SSH keys within gitolite
* Allows for the bootstrapping of a gitolite-admin repository

## Requirements ##
* Ruby 1.8.x or 1.9.x
* a working [gitolite](https://github.com/sitaramc/gitolite) installation
* the <tt>gitolite-admin</tt> repository checked out locally

## Installation ##

    gem install gitolite

## Usage ##

### Load a gitolite-admin repo ###

    require 'gitolite'
    ga_repo = Gitolite::GitoliteAdmin.new("/path/to/gitolite/admin/repo")

This method can only be called on an existing gitolite-admin repo.  If you need to create a new gitolite-admin repo, see "Bootstrapping".

### Configuration Files ###

    conf = ga_repo.config

    #Empty configs can also be initialized
    conf2 = Config.init # => defaults to a filename of gitolite.conf
    conf2 = Config.init("new_config.conf")

    #Filename is set to whatever the filename was when the config was created
    conf.filename # => "gitolite.conf"
    conf2.filename # => "new_config.conf")

    #filename can be changed via the setter
    conf2.filename = "new_config.conf"

    #to_file will write the config out to the file system
    #using the value of the filename attribute.  An alternative
    #filename can also be specified
    conf.to_file("/new/config/path") # => writes /new/config/path/gitolite.conf
    conf.to_file("/new/config/path", "test.conf") # => writes /new/config/path/test.conf

### Repo management ###

    repo = Gitolite::Config::Repo.new("AwesomeRepo")

    #For a list of permissions, see http://sitaramc.github.com/gitolite/conf.html#gitolite
    repo.add_permission("RW+", "", "bob", "joe", "susan")

    #Add repo to config
    conf.add_repo(repo)

    #Delete repo by object
    conf.rm_repo(repo)

    #Delete a repo by name
    conf.rm_repo("AwesomeRepo")
    conf.rm_repo(:AwesomeRepo)

    #Test if repo exists by name
    conf.has_repo?('cool_repo') # => false
    conf.has_repo?(:cool_repo) # => false

    #Can also pass a Gitolite::Config::Repo object
    repo = Gitolite::Config::Repo.new('cool_repo')
    conf.has_repo?(repo) # => true

    #Get a repo object from the config
    repo = conf.get_repo('cool_repo')
    repo = conf.get_repo(:cool_repo)

### SSH Key Management ###

    #Three ways to create keys: manually, from an existing key, or from a string representing a key
    key = Gitolite::SSHKey.new("ssh-rsa", "big-public-key-blob", "email")
    key2 = Gitolite::SSHKey.from_file("/path/to/ssh/key.pub")

    key_string = File.read("/path/to/ssh/key.pub")
    key3 = Gitolite::SSHKey.from_string(key_string, "owner")


    #Add the keys
    ga_repo.add_key(key)
    ga_repo.add_key(key2)
    ga_repo.add_key(key3)

    #Remove key2
    ga_repo.rm_key(key2)

### Save changes ###

    ga_repo.save

When this method is called, all changes get written to the file system and staged in git.  For the time being, gitolite assumes full control of the gitolite-admin repository.  This means that any keys in the keydir that are not being tracked will be removed and any human changes to gitolite.conf will be erased.

### Apply changes ###
    ga_repo.apply

This method will commit all changes with a generic message (will be improved upon later) and push to <tt>origin master</tt>.

### Save and apply ###
    ga_repo.save_and_apply

### Updating remote changes ###
    #In order to avoid conflicts, this will perform a reset! by default
    #pass :reset => false to disable the reset (Git conflicts will have to be manually fixed)
    ga_repo.update
    ga_repo.update(:reset => false)

    #Update while performing a rebase
    ga_repo.update(:rebase => true)

### Reloading from the file system ###
    ga_repo.reload!

### Resetting to HEAD, destroying all local changes (including untracked files) ###
    #This will also perform a reload!
    ga_repo.reset!

### Bootstrapping ###
    ga_repo = GitoliteAdmin.bootstrap("/path/to/new/gitolite/repo")

This will create the folders <tt>conf</tt> and <tt>keydir</tt> in the supplied path.  A config file will also be created in the conf directory.  The default configuration supplies RW+ permissions to a user named git for a repo named <tt>gitolite-admin</tt>.  You can specify an options hash to change some values:

    ga_repo = GitoliteAdmin.bootstrap("/path/to/new/gitolite/repo", {:user => "admin", :perm => "RW"})

You can also pass a message to be used for the initial bootstrap commit:

    ga_repo = GitoliteAdmin.bootstrap("/path/to/new/gitolite/repo", {:message => "Bootstrapped new repo"})

Please note that while bootstrapping is supported, I highly recommend that the initial gitolite-admin repo be created by gitolite itself.

## Caveats ##
### Windows compatibility ###
The grit gem (which is used for under-the-hood git operations) does not currently support Windows.  Until it does, gitolite will be unable to support Windows.

### Group Ordering ###
When the gitolite backend parses the config file, it does so in one pass.  Because of this, groups that are modified after being used do not see those changes reflected in previous uses.

For example:

    @groupa = bob joe sue
    @groupb = jim @groupa
    @groupa = sam

Group b will contain the users <tt>jim, bob, joe, and sue</tt>

The gitolite gem, on the other hand, will <em>always</em> output groups so that all modifications are represented before it is ever used.  For the above example, group b will be output with the following users: <tt>jim, bob, joe, sue, and sam</tt>.  The groups in the config file will look like this:

    @groupa = bob joe sue sam
    @groupb = jim @groupa

## Issues ##
* Gem is not thread safe.  For now, the gem will change directories in order to perform git operations.  It will, however, return to the old working directory once it is finished.  I am looking into making the gem thread safe.  Note that this is only an issue on Rubies that do not have a GIL (ex jRuby or Rubinius)

# Contributing #
* Tests!  If you ask me to pull changes that are not adequately tested,  I'm not going to do it.
* If you introduce new features/public methods on objects, you must update the README.

### Contributors ###
* Alexander Simonov - [simonoff](https://github.com/simonoff)

## Documentation ##
* Rdoc is coming eventually

## Future ##
* support folders in the keydir
* support include tags
* cleanup methods to make adding and removing easier (like add_key should accept an array of keys)
* Make the gem thread safe
* Rails integration via [gitolite-rails](https://www.github.com/wingrunr21/gitolite-rails)
