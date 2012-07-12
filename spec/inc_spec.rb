describe Gitolite::Config do
  conf_dir = File.join(File.dirname(__FILE__),'configs')

  describe "include managment" do
    before :each do
      @root_config = Gitolite::Config.load_from(File.join(conf_dir, 'incs.conf'))
      @root_config.has_inc?('foo.conf').should == true
      @foo_config =  @root_config.get_inc 'foo.conf'
    end

    describe '#load_from' do
      it 'should has a sub-configuration' do
        @root_config.includes.length.should == 3
        @root_config.has_inc?('foo.conf').should == true
        foo = @root_config.get_inc 'foo.conf'
        foo.class.should == Gitolite::Config
        foo.groups.length.should == 1
        foo.parent.should be @root_config
        foo.includes.length.should == 1
      end

      it 'should have a wildchar matched subconf' do
        @root_config.has_inc?('wild/*.conf').should == true
        wilds= @root_config.get_inc('wild/*.conf')
        wilds.class.should == Gitolite::Config
        wilds.includes.length.should == 2
        wilds.has_inc?('wild1.conf').should == true
        wilds.has_inc?('hiwild.conf').should == true
      end


      it 'should has a repos in subconf foo' do
          r = @foo_config.get_repo('foo')
          r.owner.should == "Mkie LEE"
          r.description.should == "This is a cool foo."
      end


      it 'should raise error when subconfig recursive include' do
        expect{Gitolite::Config.load_from(File.join(conf_dir, 'sparent.conf'))}.to raise_error(Gitolite::Config::ConfigDependencyError)
      end
    end

    describe "#get_relative_path" do
      it 'should get proper key from file' do
        f = File.join(conf_dir, 'foo.conf')
        @root_config.get_relative_path(f).should == 'foo.conf'
        @root_config.normalize_config_name('foo.conf').should == 'foo.conf'
        @root_config.includes.has_key?('foo.conf').should be true
        @root_config.includes.has_key?(@root_config.get_relative_path('foo.conf')).should be true
        @root_config.has_inc?('foo.conf').should == true
        @root_config.has_inc?(f).should == true
      end
    end

    describe '#get_inc' do
      it 'should fetch a subconf by a string containing the relatived filename' do
        @root_config.get_inc('foo.conf').should be_an_instance_of Gitolite::Config
      end

      it 'should fetch a subconf by a string containing the absoluted filename' do
        f = File.join(conf_dir, 'foo.conf') # make the absoluted path file name.
        @root_config.get_inc(f).should be_an_instance_of Gitolite::Config
      end

      it 'should fetch a subconf via a symbol representing the name' do
        # todo maybe ignore the ext name in symbol? use ":foo" means "foo.conf"
        @root_config.get_inc(:'foo.conf').should be_an_instance_of Gitolite::Config
      end

      it 'should return nil for a subconf that does not exist' do
        @root_config.get_inc(:none).should be nil
      end
    end

    describe "#has_inc?" do
      it 'should return false for a subconf that does not exist' do
        @root_config.has_inc?(:none).should be false
      end

      it 'should check for the existance of a subconf given a subconf object' do
        r = @root_config.get_inc("foo.conf")
        @root_config.has_inc?(r).should be true
      end

      it 'should check for the existance of a subconf given a string containing the name' do
        @root_config.has_inc?('foo.conf').should be true
      end

      it 'should check for the existance of a subconf given a symbol representing the name' do
        @root_config.has_inc?(:'foo.conf').should be true
      end
    end

    describe "#add_inc" do
      it 'should throw an ArgumentError for non-Gitolite::Config objects passed in' do
        lambda{ @root_config.add_inc("not-a-config") }.should raise_error(ArgumentError)
      end

      it 'should add a given conf to the list of includes' do
        r = Gitolite::Config.new('cool_config')
        n = @root_config.includes.size
        @root_config.add_inc(r)

        @root_config.includes.size.should == n + 1
        @root_config.has_inc?(:cool_config).should be true
      end

      it 'should raise a ConfigDependencyError if there is a cyclic dependency' do
        c = Gitolite::Config.new("test_deptree.conf")
        s = Gitolite::Config.new_inc "inc1.conf", c
        expect{s.add_inc c}.should raise_error(Gitolite::Config::ConfigDependencyError)
      end
    end
    
    describe "#rm_inc" do
      it 'should remove a subconfig for the Gitolite::Config object given' do
        g = @root_config.get_inc('foo.conf')
        g2 = @root_config.rm_inc(g)
        g.should_not be nil
        g2.name.should == g.name
      end

      it 'should remove a subconf given a string containing the name' do
        g = @root_config.get_inc('foo.conf')
        g2 = @root_config.rm_inc('foo.conf')
        g2.name.should == g.name
      end

      it 'should remove a subconf given a symbol representing the name' do
        g = @root_config.get_inc('foo.conf')
        g2 = @root_config.rm_inc(:'foo.conf')
        g2.name.should == g.name
      end
    end

    describe "#to_file" do
      it 'should ensure save includes info' do
        c = Gitolite::Config.init
        c.filename = "test_incs.conf"

        # Build some groups out of order
        s = Gitolite::Config.new_inc "inc1.conf", c
        g = Gitolite::Config::Group.new "groupa"
        g.add_users "bob", "@all"
        s.add_group(g)

        # Write the config to a file
        file = c.to_file('/tmp')
        # Read the conf and make sure our order is correct
        f = File.read(file)
        lines = f.lines.map {|l| l.strip}
        # Compare the file lines.  Spacing is important here since we are doing a direct comparision
        lines[0].should == "include    \"inc1.conf\""
        # Cleanup
        File.unlink(file)
        file = '/tmp/inc1.conf'
        f = File.read(file)
        lines = f.lines.map {|l| l.strip}

        # Compare the file lines.  Spacing is important here since we are doing a direct comparision
        lines[0].should == "@groupa             = @all bob"

        # Cleanup
        File.unlink(file)

      end

      it 'should ensure save includes info and force to create the direcotory ' do
        c = Gitolite::Config.new "test_incs.conf"

        s = Gitolite::Config.new_inc "mytest_inc/inc1.conf", c
        g = Gitolite::Config::Group.new "groupa"
        g.add_users "bob", "@all"
        s.add_group(g)

        # add a wildchar matched container
        w = Gitolite::Config.new_inc "wild/*.conf", c
        c.get_inc('wild/*.conf').should == w
        Gitolite::Config.new_inc('wild1.conf', w).add_group(g)


        # Write the config to a file
        file = c.to_file('/tmp', nil, true)
        # Read the conf and make sure our order is correct
        f = File.read(file)
        lines = f.lines.map {|l| l.strip}
        # Compare the file lines.  Spacing is important here since we are doing a direct comparision
        lines[0].should == "include    \"mytest_inc/inc1.conf\""
        lines[1].should == "include    \"wild/*.conf\""
        # Cleanup
        File.unlink(file)

        file = '/tmp/mytest_inc/inc1.conf'
        f = File.read(file)
        lines = f.lines.map {|l| l.strip}

        # Compare the file lines.  Spacing is important here since we are doing a direct comparision
        lines[0].should == "@groupa             = @all bob"

        # Cleanup
        File.unlink(file)

        #check the includes of the container file.
        file = '/tmp/wild/wild1.conf'
        f = File.read(file)
        lines = f.lines.map {|l| l.strip}

        # Compare the file lines.  Spacing is important here since we are doing a direct comparision
        lines[0].should == "@groupa             = @all bob"

        # Cleanup
        File.unlink(file)

        Dir.rmdir('/tmp/mytest_inc')

      end
    end
  end
end
