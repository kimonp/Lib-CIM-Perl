package LCP::XMLWriter;
use strict;
use warnings;
use Carp;
use XML::Twig;
use Data::Dumper;


our $VERSION = '0.00_01';
$VERSION = eval $VERSION;  # see L<perlmodstyle>


sub new {
    my $class = shift;
    my $id=shift;
    my $self = bless {
        'twig' => XML::Twig->new(),
        'query' => [],
        'id' => $id,
        'xml' => '',
        'root' => ''
    }, $class;
}

sub set_query_id($$){
    my $self=shift;
    my $id=shift;
    if($id=~/\d+/){
        if ($id lt 65536){
            $self->{'id'}=$id;
        }
    }
    
}

sub addquery{
    my $self=shift;
    my $query=shift;
    push(@{$self->{'query'}},$query);
}

sub comparedefaults($\%\%;\%){
    my $self=shift;
    my $defaults=shift;
    my $settings=shift;
    my $constrains=shift;
    my $result={};
    for my $key (keys %{$settings}){
        unless (defined $defaults->{$key}){
            warn "WARNING: \"$key\" is not a vailid field in this context\n";
            carp "WARNING: Disregarding \"$key\" because it is an invalid field\n";
        }
        elsif(defined $constrains and defined $constrains->{$key}){
            if($self->checktypeconstraints($constrains->{$key},$settings->{$key})){
                $result->{$key}=$settings->{$key}
            }
            else{
                carp "ERROR: \"$settings->{$key}\" does not meet the value constraints for $key\n ";
            }
        }
        else{
           $result->{$key}=$settings->{$key} 
        }
        
    }
    for my $key (keys %{$defaults}){
        unless (defined $result->{$key}){
            $result->{$key}=$defaults->{$key}
        }
    }
    return $result;
}

sub checktwigref($\@$){
    my $self=shift;
    my $types=shift;
    my $reference=shift;
    my $regex='(' . join('|',@{$types}) . ')';
    if (ref($reference)){
        if (ref($reference)=~/^XML::Twig::Elt$/){
            if ($reference->gi =~/^$regex$/){
                return 1;
            }
            else{
                carp "ERROR: \"@{[$reference->gi]}\" tag is not valid in this context\n";
                warn "ERROR: The \"@{[$reference->gi]}\" tag is invalid\n";
                return 0;
            }
        }
    }
    return 0;
}

sub mkiparam($$;$){
    my $self=shift;
    my $name=shift;
    my $value=shift;
    my $param=XML::Twig::Elt->new('IPARAMVALUE'=>{'NAME'=>$name});
    if (defined $value){
        if (ref($value)){
            if (ref($value)=~/^XML::Twig::Elt$/){
                if ($value->gi =~/^(VALUE|VALUE.ARRAY|VALUE.REFERENCE|INSTANCENAME|CLASSNAME|QUALIFIER.DECLARATION|CLASS|INSTANCE|VALUE.NAMEDINSTANCE)$/){
                    $value->paste($param);
                }
                else{
                    carp "ERROR: \"@{[$value->gi]}\" is not a valid sub tag of an IPARAMVALUE\n";
                    warn "FAILED: Failed to create IPARAMVALUE $name due to invalid subtag";
                    return;
                }
            }
            elsif(ref($value)=~/^ARRAY$/){
                my $valuearray=$self->mkvaluearray($value);
                $valuearray->paste($param);
            }
            else{
                carp "ERROR: \"@{[ref($value)]}\" is not a valid reference type generate a subtag for an IPARAMVALUE\n";
                warn "FAILED: Failed to create IPARAMVALUE $name due to invalid subtag";
                return;
            }
        }
        else{
            my $valuetag=XML::Twig::Elt->new('VALUE'=>$value);
            $valuetag->paste($param);
        }
        
    }
    return $param;
}

sub mkmethodcall($$;*\@){
    my $self=shift;
    my $name=shift;
    my $namespace=shift;
    my $params=shift;
    my $method=XML::Twig::Elt->new('IMETHODCALL',{'NAME' => $name});
    if (defined $namespace and $namespace){
        if (ref($namespace) and ref($namespace)=~/^XML::Twig::Elt$/ and $namespace->gi =~/^(LOCALNAMESPACEPATH|LOCALCLASSPATH)$/){
            $namespace->paste($method);
        }
        elsif(ref($namespace)){
            carp "ERROR: \"@{[ref($namespace)]}\" is an invalid reference type to define an namespace for an IMETHODCALL\n";
            warn "FAILED: Failed to create IMETHODCALL $name because of invlid refernece used to define the namespace\n"
        }
        else{
            my $namespacetag=$self->mklocalnamespace($namespace);
            unless ($namespacetag){
                die "CRITICAL: could not create a namespace for \"$name\"";
            }
            $namespacetag->paste(first_child => $method);
        }
        
    }
    if (defined $params){
        for my $iparam (@{$params}){
            if (defined){
                if(ref($iparam) and ref($iparam)=~/^XML::Twig::Elt$/ and $iparam->gi =~/^IPARAMVALUE$/){
                    $iparam->paste(last_child => $method);
                }
                elsif(ref($iparam) and $iparam=~/^HASH$/ and exists $iparam->{'NAME'} and exists $iparam->{'VALUE'}){
                    my $iparamxml=$self->mkiparam($iparam->{'NAME'},$iparam->{'VALUE'});
                    $iparamxml->paste(last_child => $method);
                }
                elsif(ref($iparam)){
                    carp "WARNING: A \"@{[ref($iparam)]}\" reference cann not be used to create a valid IPARAMVALUE\n";
                    warn "ERORR: could not generate one of the IPARAMVALUE fields in IMETHODCALL $name because of incorrect input\n";
                    
                }
                else{
                    carp "WARNING: \"$iparam\" is insufficient information to create an IPARAMVALUE\n";
                    warn "ERORR: could not generate one of the IPARAMVALUE fields in IMETHODCALL $name because of incorrect input\n";
                }
            }
        }
        
    }
    return $method;
}

# requieres 1 argument the CIM name space for example root/CIM_v2
# returns an xml twig element for the formated namespace
# example
# my $namespace=mklocalnamespace('root/CIM_v2');

sub mklocalnamespace{
    my $self=shift;
    my $namespaceraw=shift;
    my @namearray=split('/',$namespaceraw);
    my $namespace= XML::Twig::Elt->new('LOCALNAMESPACEPATH');
    for my $name (@namearray){
        my $xmlname= XML::Twig::Elt->new('NAMESPACE'=>{'NAME'=>$name});
        $xmlname->paste( last_child => $namespace);
    }
    return $namespace;
}

sub checktypeconstraints{
    my $self=shift;
    my $constraint=shift;
    my $value=shift;
    if ($constraint=~/^CIMType$/){
        if ($value=~/^(boolean|string|char16|uint8|sint8|uint16|sint16|uint32|sint32|uint64|sint64|datetime|real32|real64)$/){
            return 1;
        }
        else {
            return 0;
        }
    }
    elsif ($constraint=~/^ParamType$/){
        if ($value=~/^(boolean|string|char16|uint8|sint8|uint16|sint16|uint32|sint32|uint64|sint64|datetime|real32|real64|reference|object|instance)$/){
            return 1;
        }
        else {
            return 0;
        }
    }
    elsif ($constraint=~/^ParamType/){
        if ($value=~/^(boolean|string|char16|uint8|sint8|uint16|sint16|uint32|sint32|uint64|sint64|datetime|real32|real64|reference|object|instance)$/){
            return 1;
        }
        else {
            return 0;
        }
    }
    elsif ($constraint=~/^TF$/){
        if ($value=~/^(true|false)$/){
            return 1;
        }
        else {
            return 0;
        }
    }
    elsif ($constraint=~/^boolean$/){
        if ($value=~/^(1|0)$/){
            return 1;
        }
        else {
            return 0;
        }
    }
}

sub mkvaluearray($\@){
    my $self=shift;
    my $array=shift;
    my $valuearray=XML::Twig::Elt->new('VALUE.ARRAY');
    for my $value (@{$array}){
        if (defined $value and $value!~/^NULL$/){
            my $valueitem=XML::Twig::Elt->new('VALUE'=>$value);
            $valueitem->paste( last_child => $valuearray);
        }
        else{
            my $valueitem=XML::Twig::Elt->new('VALUE.NULL');
            $valueitem->paste( last_child => $valuearray);
        }
    }
    return $valuearray;
}

sub mkkeybinding{
    my $self=shift;
    my $keys=shift;
    my @keybindings;
    if(ref $keys  eq 'HASH'){
        KEYBINDING: for my $key (keys %{$keys}){
            if (ref($keys->{$key})){
                if (ref($keys->{$key}) eq 'HASH'){
                    if (defined $keys->{$key}->{'VALUE'} or defined $keys->{$key}->{'VALUE.REFERENCE'}){
                        my $keybinding=XML::Twig::Elt->new('KEYBINDING'=>{'NAME'=>$key});
                        my $valueref;
                        if (exists $keys->{$key}->{'VALUE'}){
                            if(ref($keys->{$key}->{'VALUE'})){
                                carp "ERROR: The value of a keybinding can not be a @{[ref($keys->{$key}->{'VALUE'})]} reference it must be a STRING\n";
                                carp "WARNING: Skipping keybinding $key because it has an invalid value\n";
                                next KEYBINDING;
                            }
                            # this else isnt realy neaded but I put it in so people reading the code wouldnt be confused.
                            else{
                                my $valueref=XML::Twig::Elt->new('KEYVALUE'=>$keys->{$key}->{'VALUE'});
                            }
                            if(defined $keys->{$key}->{'VALUETYPE'} and $keys->{$key}->{'VALUETYPE'}=~/^(string|boolean|numeric)$/){
                                $valueref->set_att('VALUETYPE'=>$keys->{$key}->{'VALUETYPE'});
                            }
                            elsif(defined $keys->{$key}->{'VALUETYPE'}){
                                carp "WARNING: \"$keys->{$key}->{'VALUETYPE'})\" is not a valid VALUETYPE\n";
                                carp "WARNING: setting the VALUETYPE to string for key $key because its contents are invalid\n";
                                $valueref->set_att('VALUETYPE'=>'string');
                            }
                            else{
                                $valueref->set_att('VALUETYPE'=>'string');
                            }
                            if (defined $keys->{$key}->{'TYPE'} and $self->checktypeconstraints('CIMType',$keys->{$key}->{'TYPE'})){
                                $valueref->set_att('TYPE'=>$keys->{$key}->{'TYPE'});
                            }
                            elsif(defined $keys->{$key}->{'TYPE'}){
                                carp("ERROR: \"$keys->{$key}->{'TYPE'}\" is not a valid choice for a TYPE attribute");
                                carp ("WARNING: not including the TYPE field for keybinding $key because its contents are invalid\n");
                            }
                        }
                        elsif(defined $keys->{$key}->{'VALUE.REFERENCE'} and ref($keys->{$key}->{'VALUE.REFERENCE'})=~/^XML::Twig::Elt$/ and ($keys->{$key}->{'VALUE.REFERENCE'}->gi =~/^(CLASSPATH|LOCALCLASSPATH|CLASSNAME|INSTANCEPATH|LOCALINSTANCEPATH|INSTANCENAME)$/)){
                            my $keyref=XML::Twig::Elt->new('VALUE.REFERENCE');
                            $keys->{$key}->{'VALUE.REFERENCE'}->paste(last_child => $keyref);
                            #$valueref->paste( last_child => $keybinding);
                        }
                        elsif(defined $keys->{$key}->{'VALUE.REFERENCE'} and ref($keys->{$key}->{'VALUE.REFERENCE'})=~/^XML::Twig::Elt$/){
                            carp "WARNING: \"@{[$keys->{$key}->{'VALUE.REFERENCE'}->gi]}\" is not a valid reference type for keybinding\n";
                            carp "WARNING skipping kebinding $keys->{$key}->{'NAME'} because it has an invalid VALUE.REFERENCE\n";
                            next KEYBINDING;
                        }
                        $valueref->paste( last_child => $keybinding);
                        push(@keybindings,$keybinding);
                    }
                    else {
                            carp "ERROR: skipping keybinding $key because it has no VALUE or VALUE.REFERENCE defined.\n";
                            next KEYBINDING;
                    }
                }
                elsif(defined $keys->{$key} and ref($keys->{$key})=~/^XML::Twig::Elt$/ and $keys->{$key}->gi =~/^(CLASSPATH|LOCALCLASSPATH|CLASSNAME|INSTANCEPATH|LOCALINSTANCEPATH|INSTANCENAME)$/ ){
                    my $keybinding=XML::Twig::Elt->new('KEYBINDING'=>{'NAME'=>$key});
                    my $keyref=XML::Twig::Elt->new('VALUE.REFERENCE');
                    $keys->{$key}->paste(ast_child => $keyref);
                    $keyref->paste( last_child => $keybinding);
                    push(@keybindings,$keybinding);
                }
                elsif (ref($keys->{$key})=~/^XML::Twig::Elt$/){
                        carp "ERROR: \"@{[$keys->{$key}->gi]}\" is not a valid VALUE.REFERENCE type for keybinding\n";
                    }
                else{
                    carp "ERROR:skipping keybinding $key because \"@{[ref($keys->{$key})]}\"is not a valid reference type in this context\n";
                }
            }
            else{
                my $keybinding=XML::Twig::Elt->new('KEYBINDING'=>{'NAME'=>$key});
                #$newkey->set_att('NAME'=>$key);
                if(exists $keys->{$key}){
                    my $keyvalue=XML::Twig::Elt->new('KEYVALUE'=>{'VALUETYPE'=>'string'},$keys->{$key});
                    $keyvalue->paste( last_child => $keybinding);
                }
                else{
                    carp "WARNING: No VALUE or VALUE.REFERENCE defined for keybinding $key skipping the keybinding\n";
                    next KEYBINDING;
                }
                push(@keybindings,$keybinding);
            }
        }
    }
    elsif(ref($keys)  eq 'ARRAY'){
        KEYBINDINGARRAY: for my $key (@{$keys}){
            if (ref($key) eq 'HASH'){
                if (defined $key->{'NAME'} and (exists $key->{'VALUE'} or exists $key->{'VALUE.REFERENCE'} )){
                    my $keybinding=XML::Twig::Elt->new('KEYBINDING'=>{'NAME'=>$key->{'NAME'}});
                    my $valueref;
                    if (exists $key->{'VALUE'}){
                        if(ref($key->{'VALUE'})){
                            carp "ERROR: The VALUE of a keybinding can not be a @{[ref($key->{'VALUE'})]} reference it must be a STRING\n";
                            carp "WARNING: Skipping keybinding $key->{'NAME'} because it has an invalid VALUE\n";
                            next KEYBINDINGARRAY;
                        }
                        else{
                            $valueref=XML::Twig::Elt->new('KEYVALUE'=>$key->{'VALUE'});
                            if(defined $key->{'VALUETYPE'} and $key->{'VALUETYPE'}=~/^(string|boolean|numeric)$/){
                                $valueref->set_att('VALUETYPE'=>$key->{'VALUETYPE'});
                            }
                            elsif(defined $key->{'VALUETYPE'}){
                                carp "WARNING: \"$key->{'VALUETYPE'})\" is not a valid VALUETYPE\n";
                                carp "WARNING: setting the VALUETYPE to string for key $key->{'NAME'} because its contents are invalid\n";
                                $valueref->set_att('VALUETYPE'=>'string');
                            }
                            else{
                                $valueref->set_att('VALUETYPE'=>'string');
                            }
                            if (defined $key->{'TYPE'} and $self->checktypeconstraints('CIMType',$key->{'TYPE'})){
                                $valueref->set_att('TYPE'=>$key->{'TYPE'});
                            }
                            elsif(defined $key->{'TYPE'}){
                                carp("WARNING: \"$key->{'TYPE'}\" is not a valid choice for a TYPE attribute");
                                carp ("WARNING: not including the TYPE field for keybinding $key->{'NAME'} because its contents are invalid\n");
                            }
                        }
                    }
                    elsif(defined $key->{'VALUE.REFERENCE'} and ref($key->{'VALUE.REFERENCE'})=~/^XML::Twig::Elt$/ and ($key->{'VALUE.REFERENCE'}->gi =~/^(CLASSPATH|LOCALCLASSPATH|CLASSNAME|INSTANCEPATH|LOCALINSTANCEPATH|INSTANCENAME)$/)){
                        $valueref=XML::Twig::Elt->new('VALUE.REFERENCE');
                        $key->{'VALUE.REFERENCE'}->paste(last_child => $valueref);
                    }
                    elsif(defined $key->{'VALUE.REFERENCE'} and ref($key->{'VALUE.REFERENCE'})=~/^XML::Twig::Elt$/){
                        carp "WARNING: \"@{[$key->{'VALUE.REFERENCE'}->gi]}\" is not a valid reference type for keybinding\n";
                        carp "WARNING skipping kebinding $key->{'NAME'} because it has an invalid VALUE.REFERENCE\n";
                        next KEYBINDINGARRAY;
                    }
                    
                    $valueref->paste( last_child => $keybinding);
                    push(@keybindings,$keybinding);
                }
                else{
                    carp "ERROR: A Keybinding is missing requierd fields skipping the current keybinding";
                    next KEYBINDINGARRAY;
                }
            }
            else{
                carp "ERROR: A Keybinding is missing requierd fields skipping the current keybinding";
                next KEYBINDINGARRAY;
            }
        }
        
    }
    if (wantarray){
        return @keybindings;
    }
    else{
        return \@keybindings;
    }
}


sub mkbool{
    my $self=shift;
    my $hash=shift;
    my @params;
    for my $key (keys %{$hash}){
        if ($hash->{$key}){
            my $param=$self->mkiparam($key,'TRUE');
            push(@params,$param);
        }
        else{
            my $param=$self->mkiparam($key,'FALSE');
            push(@params,$param);
        }
    }
    return @params;
}

sub mkproperty($$;$$$$$){
    my $self=shift;
    my $name=shift;
    my $value=shift;
    my $type=shift;
    my $originclass=shift;
    my $propagated=shift;
    my $lang=shift;
    # attribs to add
    # CLASSORIGIN #IMPLIED
    #PROPAGATED     (true|false)  'false'
    #EmbeddedObject (object|instance) #IMPLIED
    # xml:lang   NMTOKEN     #IMPLIED
    unless(defined $type){
        $type='string';
    }
    else{
        unless ($self->checktypeconstraints('CIMType',$type)){
            carp "ERROR: \"$type\" is not a valid CIM Type\n";
            warn "WARNING: setting the type to string for PROPERTY name $name because the type is invalid\n";
            $type='string';
        }
    }
    my $param=XML::Twig::Elt->new('PROPERTY'=>{'NAME'=>$name,'TYPE'=>$type});
    if (defined $value){
        my $val=XML::Twig::Elt->new('VALUE'=>$value);
        $val->paste($param);
    }
    if (defined $originclass){
        $param->set_att('CLASSORIGIN'=>$originclass);
        
    }
    if (defined $propagated){
        if ($self->checktypeconstraints('bool',$propagated)){
            if ($propagated){
                $param->set_att('PROPAGATED'=>'true');
            }
            else{
                $param->set_att('PROPAGATED'=>'false');
            }
        }
        elsif($self->checktypeconstraints('TF',$propagated)){
            $param->set_att('PROPAGATED'=>$propagated);
        }
        else{
            carp "ERROR: \"$propagated\" is not a true, false, or bool value\n";
            warn "WARNING: skipping the PROPAGATED for PROPERTY $name bacause of invalid value\n";
        }
        
    }
    if(defined $lang){
        $param->set_att('xml:lang'=>$lang);
    }
    return $param;
}

sub mkqualifier($$;$$$\%$){
    my $self=shift;
    my $name=shift;
    my $value=shift;
    my $type=shift;
    my $propagated=shift;
    my $rawflavor=shift;
    my $lang=shift;
    my $defaultflavor={
        'OVERRIDABLE'=>'true',
        'TOSUBCLASS'=>'true',
        'TOINSTANCE'=>'false',
        'TRANSLATABLE'=>'false'
    };
    my $flavorconstraints={
        'OVERRIDABLE'=>'TF',
        'TOSUBCLASS'=>'TF',
        'TOINSTANCE'=>'TF',
        'TRANSLATABLE'=>'TF'
    };
    my $flavor=$self->comparedefaults($defaultflavor,$rawflavor,$flavorconstraints);
    unless(defined $type){
        $type='string';
    }
    else{
        unless ($self->checktypeconstraints('CIMType',$type)){
            carp "ERROR: \"$type\" is not a valid CIM Type\n";
            warn "WARNING: setting the Type to string because of invalid input\n";
            $type='string';
        }
    }
    my $qualifier=XML::Twig::Elt->new('QUALIFIER'=>{'NAME'=>$name,'TYPE'=>$type});
    for my $key (keys %{$flavor}){
        $qualifier->set_att($key=>$flavor->{$key});
    }
    if(defined $propagated and $propagated){
        $qualifier->set_att('PROPAGATED'=>'true');
    }
    else{
        $qualifier->set_att('PROPAGATED'=>'false');
    }
    if(defined $lang){
        $qualifier->set_att('xml:lang'=>$lang);
    }
    if (defined $value){
        if ($self->checktwigref(['VALUE','VALUE.ARRAY'],$value)){
            $value->paste(last_child => $qualifier);
        }
        elsif(ref($value)){
            if (ref($value) eq 'ARRAY'){
                my $valuexml=$self->mkvaluearray($value);
                $valuexml->paste(last_child => $qualifier);
            }
            elsif(ref($value) eq 'XML::Twig::Elt'){
                carp "ERROR: @{[$value->gi]} is not a valid subtag fora qualifier\n";
            }
            else{
                carp "ERROR: The value of a qualifier can not be defined in a @{[ref($value)]} reference\n";
            }
        }
        else{
            my $valuexml=XML::Twig::Elt->new('VALUE'=>$value);
            $valuexml->paste(last_child => $qualifier);
        }
    }
    return $qualifier;
}

sub mkpropertylist($\@){
    my $self=shift;
    my $array=shift;
    my $param=$self->mkiparam('PropertyList',$array);
    #my $param=XML::Twig::Elt->new('IPARAMVALUE'=>{'NAME'=>'PropertyList'});
    #my $valuearray=$self->mkvaluearray($array);
    #$valuearray->paste( last_child => $param);
    return $param;
}

sub mkclassname{
    my $self=shift;
    my $rawclassname=shift;
    my $param=$self->mkiparam('ClassName',XML::Twig::Elt->new('CLASSNAME'=>{'NAME'=>$rawclassname}));
    #my $param=$self->mkiparam('ClassName');
    #my $classname=XML::Twig::Elt->new('CLASSNAME'=>{'NAME'=>$rawclassname});
    #$classname->paste($param);
    return $param;
}

sub mkobjectname{
    my $self=shift;
    my $rawclassname=shift;
    my $value=shift;
    #my $param=$self->mkiparam('ObjectName');
    my $classname=XML::Twig::Elt->new('INSTANCENAME'=>{'CLASSNAME'=>$rawclassname});
    #$classname->paste('last_child'=>$param);
    if ($value){
        if (ref($value) eq 'ARRAY'){
            for my $val (@{$value}){
                $val->paste('last_child'=>$classname);
            }
        }
        else{
            $value->paste('last_child'=>$classname);
        }
    }
    my $param=$self->mkiparam('ObjectName',$classname);
    return $param;
}

sub mkinstancename{
    my $self=shift;
    my $rawclassname=shift;
    my $value=shift;
    my $param=$self->mkiparam('InstanceName');
    my $classname=XML::Twig::Elt->new('INSTANCENAME'=>{'CLASSNAME'=>$rawclassname});
    $classname->paste('last_child'=>$param);
    if ($value){
        if (ref($value) eq 'ARRAY'){
            for my $val (@{$value}){
                $val->paste('last_child'=>$classname);
            }
        }
        else{
            $value->paste('last_child'=>$classname);
        }
    }
    return $param;
}

sub mkassocclass{
    my $self=shift;
    my $rawclassname=shift;
    my $param=$self->mkiparam('AssocClass');
    my $classname=XML::Twig::Elt->new('CLASSNAME'=>{'NAME'=>$rawclassname});
    $classname->paste($param);
    return $param;
}

sub mkresultclass{
    my $self=shift;
    my $rawclassname=shift;
    my $param=$self->mkiparam('ResultClass');
    my $classname=XML::Twig::Elt->new('CLASSNAME'=>{'NAME'=>$rawclassname});
    $classname->paste($param);
    return $param;
}

sub mkrole{
    my $self=shift;
    my $value=shift;
    my $param=$self->mkiparam('Role',$value);
    #my $param=$self->mkiparam('Role');
    #my $classname=XML::Twig::Elt->new('VALUE'=>$value);
    #$classname->paste($param);
    return $param;
}

sub mkresultrole{
    my $self=shift;
    my $value=shift;
    my $param=$self->mkiparam('ResultRole',$value);
    #my $param=$self->mkiparam('ResultRole');
    #my $classname=XML::Twig::Elt->new('VALUE'=>$value);
    #$classname->paste($param);
    return $param;
}

sub mkpropertyname{
    my $self=shift;
    my $value=shift;
    my $param=$self->mkiparam('PropertyName',$value);
    #my $param=$self->mkiparam('PropertyName');
    #my $classname=XML::Twig::Elt->new('VALUE'=>$value);
    #$classname->paste($param);
    return $param;
}

sub mkpropertyvalue{
    my $self=shift;
    my $value=shift;
    my $param=$self->mkiparam('NewValue',$value);
    #my $param=$self->mkiparam('NewValue');
    #my $classname=XML::Twig::Elt->new('VALUE'=>$value);
    #$classname->paste($param);
    return $param;
}

sub mknewinstance($$\%){
    my $self=shift;
    my $class=shift;
    my $params=shift;
    my $newinstance=$self->mkiparam('NewInstance');
    my $classname=XML::Twig::Elt->new('INSTANCE',{'CLASSNAME' => $class});
    $classname->paste('last_child' => $newinstance);
    for my $propname (keys %{$params}){
        my $prop=$self->mkproperty($propname,$params->{$propname},'string');
        $prop->paste('last_child' => $classname);
    }
    return $newinstance;
}

sub mkdelinstance($$\%){
    my $self=shift;
    my $class=shift;
    my $params=shift;
    my $delinstance=$self->mkiparam('InstanceName');
    my $instancename=XML::Twig::Elt->new('INSTANCENAME',{'CLASSNAME' => $class});
    $instancename->paste('last_child' => $delinstance);
    my $keybindings=$self->mkkeybinding($params);
    if ($keybindings){
        if (ref($keybindings) eq 'ARRAY'){
            for my $val (@{$keybindings}){
                $val->paste('last_child'=>$instancename);
            }
        }
        else{
            print Dumper($keybindings) ."\n"; 
            $keybindings->paste('last_child'=>$instancename);
        }
    }
    #for my $keybinding (@{[$keybindings]}){
    #    $keybinding->paste('last_child' => $instancename);
    #}
    return $delinstance;
}


sub generatetree{
    my $self=shift;
    my $messageid=shift;
    unless (defined $messageid and $messageid=~/^\d+$/){
        if (defined $messageid){
            carp "Invalid message id \"$messageid\"\n";
            return 0;
        }
        elsif(defined $self->{'id'} and $self->{'id'}=~/^\d+$/ ){
            $messageid=$self->{'id'};
        }
        else {
            $messageid=int(rand(65536));
        }
    }
    unless(@{$self->{'query'}}){
        carp "No CIM query defined\n";
        return 0;
    }
    $self->{'twig'}->purge;
    #$self->{'root'}=$self->{'twig'}->root;
    my $root=XML::Twig::Elt->new('CIM'=>{'CIMVERSION'=> '2.0', 'DTDVERSION' => '2.0'});
    #$root->paste( 'last_child' => $self->{'root'});
    $self->{'twig'}->set_root($root);
    $self->{'twig'}->set_xml_version('1.0');
    $self->{'twig'}->set_encoding('utf-8');
    my $message=XML::Twig::Elt->new('MESSAGE' => {'ID' => $messageid, 'PROTOCOLVERSION' => '1.0'});
    $message->paste('last_child' => $root);
    my $multireq=0;
    if (@{$self->{'query'}} > 1){
        $multireq=XML::Twig::Elt->new('MULTIREQ');
        $multireq->paste( 'first_child' => $message);
    }
    for my $rawquery (@{$self->{'query'}}){
        my $request=XML::Twig::Elt->new('SIMPLEREQ');
        if ($multireq){
            $request->paste( 'first_child' => $multireq);
        }
        else{
            $request->paste( 'first_child' => $message);
        }
        #if (defined $pointers->{$rawquery->{'type'}}){
            #print "$rawquery->{'namespace'}\n";
            #my $query=&$pointers->{$rawquery->{'type'}}->($rawquery);
            #my $query=$self->"$rawquery->{'type'}"($rawquery);
            $rawquery->paste('last_child' => $request);
        #}
        #else {carp "$rawquery->{'type'} not implemented\n";}
    }
}

sub extractxml{
    my $self=shift;
    $self->generatetree;
    my $xml=$self->{'twig'}->sprint;
}



1;

__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

LCP::XMLWriter - Lib CIM (Common Information Model) Perl XML Writer

=head1 SYNOPSIS

  use LCP::XMLWriter;
  

=head1 DESCRIPTION

This is a helper class to create XML messages to query an WBEM
provider. This class is not meant to be used by the LCP::Post class
after a query has been created by the LCP::Query class. 


=head2 EXPORT

This is an OO Class and as such it exports nothing



=head1 SEE ALSO

Please See DSP0200, DSP0201, DSP0203 from DMTF for details

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

Paul Robert Marino, E<lt>code@TheMarino.netE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Paul Robert Marino

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.14.2 or,
at your option, any later version of Perl 5 you may have available.


=cut
